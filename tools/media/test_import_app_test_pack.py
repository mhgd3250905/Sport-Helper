"""App-test import validation with private normalized fixtures, not a guessed HUB schema."""
from dataclasses import replace
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw
import import_app_test_pack as importer


class ImportAppTestPackTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / 'hub'
        self.app = self.root / 'app'
        self.source.mkdir()
        self.app.mkdir()
        for relative in ['assets/packs/old/pack.json', 'assets/training_media/v0.3.0/old.mp4',
                         'history/old.json', 'pubspec.yaml']:
            path = self.app / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'leave existing production and history alone')
        self.original = self.inventory(self.app)
        self.catalog = ('new-action-999', 'new-action-1000', 'future-unrendered')
        self.first = self.action('new-action-999')
        self.pack = self.normalized((self.first,))

    def inventory(self, root):
        return {p.relative_to(root).as_posix(): importer.digest(p)
                for p in root.rglob('*') if p.is_file()}

    def spec(self, relative):
        path = self.source / relative
        return importer.FileSpec(relative, path.stat().st_size, importer.digest(path))

    def action(self, action_id):
        root = self.source / action_id
        root.mkdir()
        (root/'packed.mp4').write_bytes(('synthetic video only for injected probe '+action_id).encode())
        for name, size in [('cover.webp', 720), ('thumb.webp', 240)]:
            image = Image.new('RGBA', (size, size))
            image.paste((200, 90, 60, 255), (size//4, size//4, size*3//4, size*3//4))
            image.save(root/name, format='WEBP', lossless=True)
        return importer.ReadyAction(action_id, self.spec(f'{action_id}/packed.mp4'),
                                    self.spec(f'{action_id}/cover.webp'), self.spec(f'{action_id}/thumb.webp'))

    def normalized(self, actions):
        # This object is the Python adapter boundary, not an external HUB manifest.
        # No fictional HUB source schema is accepted by the CLI in these fixtures.
        manifest = json.dumps({'fixtureOnly': True, 'ready': [a.id for a in actions]}).encode()
        catalog = json.dumps({'fixtureOnly': True, 'fullCatalogIds': self.catalog}).encode()
        return importer.TestPack('app-test-pack-r1', manifest, catalog, self.catalog, actions)

    def fake_probe(self, path):
        return {'codec': 'h264', 'width': 720, 'height': 1440, 'pixelFormat': 'yuv420p',
                'fps': 30, 'frames': 240, 'durationSeconds': 8,
                'colorSpace': 'bt709', 'colorRange': 'tv'}

    def fake_decoder(self, path):
        image = Image.new('RGBA', (720, 720))
        image.paste((210, 60, 40, 200), (180, 180, 540, 540))
        return image

    def run_import(self, pack=None, **options):
        return importer.import_pack(self.source, self.app, pack or self.pack,
                                    internal_opt_in=True, video_probe=self.fake_probe,
                                    frame_decoder=self.fake_decoder, **options)

    def test_preview_has_full_catalog_outside_old_93_without_writes(self):
        before = self.inventory(self.root)
        index = self.run_import()
        self.assertEqual(index['catalogIds'], sorted(self.catalog))
        self.assertEqual(list(index['actions']), ['new-action-999'])
        self.assertEqual(index['status'], 'test-unreviewed')
        self.assertIs(index['reviewed'], False)
        self.assertIs(index['releaseEligible'], False)
        self.assertIs(index['internalOnly'], True)
        self.assertEqual(before, self.inventory(self.root))

    def test_import_append_idempotent_preserves_source_stable_media_and_history(self):
        source_before = self.inventory(self.source)
        first = self.run_import(apply=True)
        self.assertEqual(first, self.run_import(apply=True))
        old_index = (self.app/'assets/app_test_pack/app-test-pack-r1/index.json').read_bytes()
        second = self.action('new-action-1000')
        combined = self.run_import(self.normalized((second,)), apply=True)
        self.assertEqual(set(combined['actions']), {'new-action-999', 'new-action-1000'})
        self.assertEqual(combined['catalogIds'], sorted(self.catalog))
        history = self.app/'assets/app_test_pack/app-test-pack-r1/history'/f'index-{hashlib.sha256(old_index).hexdigest()}.json'
        self.assertEqual(history.read_bytes(), old_index)
        self.assertEqual(source_before, {k:v for k,v in self.inventory(self.source).items() if k.startswith('new-action-999/')})
        now = self.inventory(self.app)
        for path, sha in self.original.items():
            self.assertEqual(now[path], sha)
        self.assertTrue(all(path.startswith('assets/app_test_pack/') or path in self.original for path in now))

    def test_requires_explicit_internal_opt_in(self):
        with self.assertRaisesRegex(importer.ImportError, 'production import is disabled'):
            importer.import_pack(self.source, self.app, self.pack, apply=True)
        self.assertEqual(self.original, self.inventory(self.app))

    def test_reviewed_or_release_eligible_statuses_are_rejected(self):
        for pack in [replace(self.pack, reviewed=True), replace(self.pack, release_eligible=True),
                     replace(self.pack, status='published'), replace(self.pack, reviewed=0)]:
            with self.subTest(pack=pack.status):
                with self.assertRaisesRegex(importer.ImportError, 'test-unreviewed'):
                    self.run_import(pack, apply=True)
        self.assertEqual(self.original, self.inventory(self.app))

    def test_path_escapes_windows_drives_unc_ads_and_parent_segments_are_rejected(self):
        for path in ['../outside.mp4', '/outside.mp4', 'C:/outside.mp4', '//host/share/file.mp4',
                     'a\\b.mp4', 'a/../outside.mp4', './a.mp4', 'a//b.mp4', 'a.mp4:stream']:
            with self.subTest(path=path):
                action = replace(self.first, packed_video=replace(self.first.packed_video, path=path))
                with self.assertRaisesRegex(importer.ImportError, 'Unsafe relative'):
                    self.run_import(replace(self.pack, actions=(action,)), apply=True)
        self.assertEqual(self.original, self.inventory(self.app))

    def test_size_and_sha_prevent_committing_index(self):
        wrong = replace(self.first, packed_video=replace(self.first.packed_video, sha256='0'*64))
        with self.assertRaisesRegex(importer.ImportError, 'mismatch'):
            self.run_import(replace(self.pack, actions=(wrong,)), apply=True)
        wrong = replace(self.first, alpha_cover=replace(self.first.alpha_cover, bytes=True))
        with self.assertRaisesRegex(importer.ImportError, 'Positive bytes'):
            self.run_import(replace(self.pack, actions=(wrong,)), apply=True)
        self.assertEqual(self.original, self.inventory(self.app))

    def test_producer_mutation_after_probe_does_not_commit_index(self):
        def mutating_probe(path):
            result = self.fake_probe(path)
            path.write_bytes(b'HUB is still writing this source file')
            return result
        with self.assertRaisesRegex(importer.ImportError, 'Source changed during validation|Size/SHA256 mismatch'):
            importer.import_pack(self.source, self.app, self.pack, internal_opt_in=True,
                                 apply=True, video_probe=mutating_probe, frame_decoder=self.fake_decoder)
        self.assertFalse((self.app/'assets/app_test_pack/app-test-pack-r1/index.json').exists())
        self.assertEqual(self.original, self.inventory(self.app))

    def test_actual_alpha_required_not_only_webp_extension(self):
        path = self.source/self.first.alpha_cover.path
        Image.new('RGB', (720, 720), (30, 30, 30)).save(path, 'WEBP')
        bad = replace(self.first, alpha_cover=self.spec(self.first.alpha_cover.path))
        with self.assertRaisesRegex(importer.ImportError, 'RGBA WebP'):
            self.run_import(replace(self.pack, actions=(bad,)), apply=True)
        self.assertEqual(self.original, self.inventory(self.app))

    def test_wrong_thumbnail_size_and_all_invisible_image_are_rejected(self):
        path = self.source/self.first.alpha_thumbnail.path
        for size in [120, 240]:
            Image.new('RGBA', (size, size)).save(path, 'WEBP', lossless=True)
            bad = replace(self.first, alpha_thumbnail=self.spec(self.first.alpha_thumbnail.path))
            with self.assertRaises(importer.ImportError):
                self.run_import(replace(self.pack, actions=(bad,)))

    def test_duplicate_or_out_of_catalog_actions_are_rejected(self):
        cases = [replace(self.pack, actions=(self.first, self.first)),
                 replace(self.pack, catalog_ids=('not-this-action',)),
                 replace(self.pack, catalog_ids=self.catalog+(self.catalog[0],))]
        for pack in cases:
            with self.assertRaises(importer.ImportError):
                self.run_import(pack)

    def test_existing_action_changes_and_catalog_removal_rejected_before_write(self):
        self.run_import(apply=True)
        before = self.inventory(self.app)
        path = self.source/self.first.packed_video.path
        path.write_bytes(b'different revision')
        changed = replace(self.first, packed_video=self.spec(self.first.packed_video.path))
        with self.assertRaisesRegex(importer.ImportError, 'new pack revision'):
            self.run_import(self.normalized((changed,)), apply=True)
        with self.assertRaisesRegex(importer.ImportError, 'remove previously'):
            self.run_import(replace(self.normalized((changed,)), catalog_ids=(self.first.id,)), apply=True)
        self.assertEqual(before, self.inventory(self.app))

    def test_corrupt_existing_asset_rejected_instead_of_overwritten(self):
        index = self.run_import(apply=True)
        path = self.app/index['actions'][self.first.id]['alphaCover']['asset']
        path.write_bytes(b'keep damaged file for investigation')
        before = self.inventory(self.app)
        with self.assertRaisesRegex(importer.ImportError, 'missing/corrupt'):
            self.run_import(apply=True)
        self.assertEqual(before, self.inventory(self.app))

    def test_source_symlink_is_rejected(self):
        target = self.root/'outside.mp4'
        target.write_bytes(b'not from the allowed source')
        link = self.source/'linked.mp4'
        try:
            link.symlink_to(target)
        except OSError:
            self.skipTest('Host does not permit unprivileged symlinks')
        with self.assertRaisesRegex(importer.ImportError, 'Symlink'):
            importer.relative_file(self.source, 'linked.mp4')

    def test_planning_only_and_unknown_schema_fail_closed(self):
        (self.source/'planning').mkdir()
        (self.source/'planning/existing-full-layers-r1.json').write_text('{"format":"pose-hub-stacked-alpha-plan@1"}')
        with self.assertRaisesRegex(importer.ImportError, 'not delivered yet'):
            importer.load_source(self.source)
        (self.source/'manifest.json').write_text(json.dumps({'format':'unknown@1', 'status':'test-unreviewed',
                                                           'reviewed':False, 'releaseEligible':False}))
        with self.assertRaisesRegex(importer.ImportError, 'Unsupported HUB deliverable schema'):
            importer.load_source(self.source)

    def delivery_documents(self, ready):
        """Minimal subset of the actual observed delivery/catalog@1 contract."""
        actions=[]
        for action in ready:
            qa=self.source/f'{action.id}/qa.json'
            qa.write_text('{"passed":true}',encoding='utf8')
            def record(spec,**metadata):
                return {'path':spec.path,'bytes':spec.bytes,'sha256':spec.sha256,**metadata}
            actions.append({'id':action.id,'reviewed':False,'releaseEligible':False,'availableForApp':True,
                'fps':30,'frames':240,'durationSeconds':8,
                'files':{'video':record(action.packed_video,width=720,height=1440,codec='h264',pixelFormat='yuv420p'),
                         'cover':record(action.alpha_cover,width=720,height=720,alpha=True),
                         'thumbnail':record(action.alpha_thumbnail,width=240,height=240,alpha=True)},
                'qa':{'report':record(self.spec(f'{action.id}/qa.json')),'metrics':{'passed':True}}})
        ready_ids={a.id for a in ready}
        counts={'totalCount':len(self.catalog),'readyCount':len(ready),'pendingCount':len(self.catalog)-len(ready),
                'pendingIds':sorted(set(self.catalog)-ready_ids)}
        flags={'id':'app-test-pack-r1','status':'test-unreviewed','reviewed':False,'releaseEligible':False}
        manifest={'format':'pose-hub-stacked-alpha-delivery@1',**flags,**counts,'skin':'realistic',
                  'complete':False,'sourceCatalogSha256':'a'*64,'updatedAt':'fixture-1',
                  'encoding':{'layout':'top-rgb-bottom-alpha','width':720,'height':1440,'rgbAlphaMode':'straight',
                              'alphaChannelAfterRgbDecode':'red','matrix':'bt709','range':'limited'},
                  'states':{aid:{'state':'ready-test-unreviewed' if aid in ready_ids else 'queued'} for aid in self.catalog},
                  'actions':actions}
        by_id={a['id']:a for a in actions}
        catalog={'format':'pose-hub-app-test-catalog@1',**flags,**counts,
                 'actions':[{'id':aid,'nameZh':'测试动作','muscleGroups':['abs'],'equipment':['mat'],
                             'rhythm':{'durationSeconds':8,'execution':None,'videoLoopIsTrainingDose':False},
                             'state':'ready-test-unreviewed' if aid in ready_ids else 'existing-full-layers-ready-to-encode',
                             'availableForApp':aid in ready_ids,'reviewed':False,'releaseEligible':False,
                             **({'files':by_id[aid]['files']} if aid in ready_ids else {})} for aid in self.catalog]}
        return manifest,catalog

    def write_delivery(self,manifest,catalog):
        (self.source/'manifest.json').write_text(json.dumps(manifest),encoding='utf8')
        (self.source/'catalog.json').write_text(json.dumps(catalog),encoding='utf8')

    def test_observed_schema_keeps_full_catalog_but_never_discovers_stray_media(self):
        self.action('future-unrendered') # Files exist, but no delivered record claims them.
        manifest,catalog=self.delivery_documents((self.first,))
        self.write_delivery(manifest,catalog)
        pack=importer.load_source(self.source)
        self.assertEqual(pack.catalog_ids,tuple(sorted(self.catalog)))
        self.assertEqual([a.id for a in pack.actions],[self.first.id])
        index=importer.import_pack(self.source,self.app,pack,internal_opt_in=True,apply=True,
                                  video_probe=self.fake_probe,frame_decoder=self.fake_decoder,
                                  skip_unverified_ready=True)
        self.assertEqual(set(index['actions']),{self.first.id})
        self.assertEqual(index['pendingIds'],sorted(set(self.catalog)-{self.first.id}))
        self.assertEqual((self.app/index['catalogAsset']).read_bytes(),pack.catalog)

    def test_known_schema_catalog_gate_readiness_and_encoding_must_agree(self):
        manifest,catalog=self.delivery_documents((self.first,))
        cases=[]
        changed=json.loads(json.dumps(catalog));changed['reviewed']=True;cases.append((manifest,changed))
        changed=json.loads(json.dumps(catalog));changed['actions'][0]['availableForApp']=False;cases.append((manifest,changed))
        changed=json.loads(json.dumps(manifest));changed['encoding']['alphaChannelAfterRgbDecode']='luma';cases.append((changed,catalog))
        for m,c in cases:
            with self.assertRaises(importer.ImportError):
                importer.parse_delivery(json.dumps(m).encode(),json.dumps(c).encode())

    def test_live_snapshot_retries_when_manifest_changes_between_reads(self):
        manifest,catalog=self.delivery_documents((self.first,))
        self.write_delivery(manifest,catalog)
        original=(self.source/'manifest.json').read_bytes()
        manifest['updatedAt']='fixture-2'
        latest=json.dumps(manifest).encode()
        read=Path.read_bytes
        calls=[]
        def racing_read(path):
            if path==self.source/'manifest.json':
                calls.append(path)
                return original if len(calls)==1 else latest
            return read(path)
        with patch.object(Path,'read_bytes',racing_read):
            pack=importer.load_source(self.source)
        self.assertEqual(pack.manifest,latest)
        self.assertGreaterEqual(len(calls),4)

    def test_bad_ready_record_is_reported_not_imported_while_other_ready_record_succeeds(self):
        second=self.action('new-action-1000')
        manifest,catalog=self.delivery_documents((self.first,second))
        self.write_delivery(manifest,catalog)
        (self.source/second.alpha_cover.path).write_bytes(b'still being replaced')
        pack=importer.load_source(self.source)
        index=importer.import_pack(self.source,self.app,pack,internal_opt_in=True,apply=True,
                                  video_probe=self.fake_probe,frame_decoder=self.fake_decoder,
                                  skip_unverified_ready=True)
        self.assertEqual(set(index['actions']),{self.first.id})
        report=json.loads((self.app/index['validatedMetadataAsset']).read_bytes())
        self.assertIn(second.id,report['rejectedRecords'])
        self.assertEqual(report['validatedRecordIds'],[self.first.id])
        self.assertEqual(report['catalogActionCount'],3)

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'ffmpeg/ffprobe unavailable')
    def test_real_h264_probe_accepts_packed_geometry_and_rejects_stage_video(self):
        for width, height, expected in [(720,1440,True),(720,720,False)]:
            path = self.source/f'real-{height}.mp4'
            subprocess.run([shutil.which('ffmpeg'), '-v','error','-nostdin','-f','lavfi','-i',
                f'color=c=black:s={width}x{height}:r=30','-frames:v','2','-c:v','libx264',
                '-pix_fmt','yuv420p','-threads','1',str(path)],check=True,capture_output=True,timeout=30)
            if expected:
                self.assertEqual(importer.probe_packed_video(path)['height'],1440)
            else:
                with self.assertRaisesRegex(importer.ImportError,'720x1440'):
                    importer.probe_packed_video(path)

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'ffmpeg/ffprobe unavailable')
    def test_playback_poster_is_actual_frame_zero_and_rgb_red_alpha_not_selected_cover(self):
        # Two normal poses differ: frame0 has a red figure left; the selected
        # cover uses frame1's blue figure right. Alpha includes a 0..255 ramp
        # plus a colored-mask patch, whose R differs substantially from luma.
        for frame in [0, 1]:
            image = Image.new('RGB', (720, 1440), (12, 18, 22))
            draw = ImageDraw.Draw(image)
            box = (50, 150, 260, 570) if frame == 0 else (460, 150, 670, 570)
            draw.rectangle(box, fill=(220, 50, 40) if frame == 0 else (30, 60, 220))
            for x in range(720):
                value = round(255*x/719)
                draw.line((x,720,x,1439), fill=(value,value,value))
            draw.rectangle((330,1050,390,1110),fill=(64,200,30))
            image.save(self.source/f'frame{frame}.png')
            if frame == 1:
                cover = image.crop((0,0,720,720)).convert('RGBA')
                cover.putalpha(image.crop((0,720,720,1440)).getchannel('R'))
                cover.save(self.source/self.first.alpha_cover.path, 'WEBP', lossless=True, exact=True)
        video = self.source/'normal-packed.mp4'
        subprocess.run([shutil.which('ffmpeg'),'-v','error','-nostdin','-framerate','30',
            '-start_number','0','-i',str(self.source/'frame%d.png'),'-frames:v','2',
            '-c:v','libx264','-crf','0','-pix_fmt','yuv420p','-threads','1',str(video)],
            check=True,capture_output=True,timeout=30)
        action=replace(self.first,packed_video=self.spec('normal-packed.mp4'),
                       alpha_cover=self.spec(self.first.alpha_cover.path))
        source_before=self.inventory(self.source)
        result=importer.import_pack(self.source,self.app,self.normalized((action,)),
                                    internal_opt_in=True,apply=True)
        descriptor=result['actions'][action.id]['alphaPlaybackPoster']
        self.assertEqual(descriptor['sourceSha256'],action.packed_video.sha256)
        self.assertEqual(descriptor['sourceFrame'],0)
        self.assertEqual(descriptor['sourceTimeSeconds'],0)
        self.assertEqual(descriptor['sha256'],importer.digest(self.app/descriptor['asset']))
        with Image.open(self.app/descriptor['asset']) as poster:
            self.assertEqual((poster.mode,poster.size),('RGBA',(720,720)))
            self.assertLess(poster.getchannel('A').getextrema()[0],5)
            self.assertGreater(poster.getchannel('A').getextrema()[1],250)
            self.assertGreater(poster.getpixel((100,360))[0],170) # frame0's left red pose
            self.assertLess(poster.getpixel((600,360))[2],100)   # not frame1's blue pose
            self.assertTrue(50<=poster.getpixel((360,360))[3]<=80) # mask.r, not Y/luma
            with Image.open(self.app/result['actions'][action.id]['alphaCover']['asset']) as cover:
                self.assertLess(cover.getpixel((100,360))[0],70)
        self.assertEqual(source_before,self.inventory(self.source))


if __name__ == '__main__':
    unittest.main()
