#import "RCTBridge.h"
#import "RNRecorder.h"
#import "RNRecorderManager.h"
#import "RCTLog.h"
#import "RCTUtils.h"

#import <AVFoundation/AVFoundation.h>

@implementation RNRecorder
{
   /* Required to publish events */
   RCTEventDispatcher *_eventDispatcher;

   /* SCRecorder instance */
   SCRecorder *_recorder;

   /* SCRecorder session instance */
   SCRecordSession *_session;

   /* Preview view ¨*/
   UIView *_previewView;

   /* Configuration */
   NSDictionary *_config;

   /* Camera type (front || back) */
   NSString *_device;

   /* Video format */
   NSString *_videoFormat;

   /* Video quality */
   NSString *_videoQuality;

   /* Audio quality */
   NSString *_audioQuality;

   /* Allow tap-to-focus + zooming */
   SCRecorderToolsView *_focusView;
}

#pragma mark - Init

- (instancetype)initWithEventDispatcher:(RCTEventDispatcher *)eventDispatcher
{
   if ((self = [super init])) {
      if (_recorder == nil) {
         _recorder = [SCRecorder recorder];
         _recorder.delegate = self;
         _recorder.initializeSessionLazily = NO;
         _recorder.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
         [self changeMediaType:@"photo"];  // Start in photo mode.
      }
   }
   return self;
}

-(void)dealloc
{
   // prevents: "Deactivating an audio session that has running I/O."
   [[AVAudioSession sharedInstance] setActive:NO error:nil];
   [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];
   [[AVAudioSession sharedInstance] setActive:YES error:nil];

   _recorder.previewView = nil; // !IMPORTANT! Prevents the "Cannot Encode" error.
   _recorder.delegate = nil;
}

#pragma mark - Setter

- (void)setConfig:(NSDictionary *)config
{
   _config = config;
   NSDictionary *video  = [RCTConvert NSDictionary:[config objectForKey:@"video"]];
   NSDictionary *audio  = [RCTConvert NSDictionary:[config objectForKey:@"audio"]];

   // Recorder config
   _recorder.autoSetVideoOrientation = [RCTConvert BOOL:[config objectForKey:@"autoSetVideoOrientation"]];

   // Flash config
   NSInteger flash = (int)[RCTConvert NSInteger:[config objectForKey:@"flashMode"]];
   _recorder.flashMode = flash;

   // Video config
   _recorder.videoConfiguration.sizeAsSquare = true;
   _recorder.videoConfiguration.enabled = [RCTConvert BOOL:[video objectForKey:@"enabled"]];
   _recorder.videoConfiguration.bitrate = [RCTConvert int:[video objectForKey:@"bitrate"]];
   _recorder.videoConfiguration.timeScale = [RCTConvert float:[video objectForKey:@"timescale"]];
   _videoFormat = [RCTConvert NSString:[video objectForKey:@"format"]];
   [self setVideoFormat:_videoFormat];
   _videoQuality = [RCTConvert NSString:[video objectForKey:@"quality"]];

   // Audio config
   _recorder.audioConfiguration.enabled = [RCTConvert BOOL:[audio objectForKey:@"enabled"]];
   _recorder.audioConfiguration.bitrate = [RCTConvert int:[audio objectForKey:@"bitrate"]];
   _recorder.audioConfiguration.channelsCount = [RCTConvert int:[audio objectForKey:@"channelsCount"]];
   _audioQuality = [RCTConvert NSString:[audio objectForKey:@"quality"]];

   // Audio format
   NSString *format = [RCTConvert NSString:[audio objectForKey:@"format"]];
   if ([format isEqual:@"MPEG4AAC"]) {
      _recorder.audioConfiguration.format = kAudioFormatMPEG4AAC;
   }
}

- (void)setDevice:(NSString *)device
{
   _device = device;

   if ([device isEqual:@"front"]) {
      _recorder.device = AVCaptureDevicePositionFront;
   } else if ([device isEqual:@"back"]) {
      _recorder.device = AVCaptureDevicePositionBack;
   }
}

- (void)setVideoFormat:(NSString *)format
{
   _videoFormat = format;

   if ([_videoFormat isEqual:@"MPEG4"]) {
      _videoFormat = AVFileTypeMPEG4;
   } else if ([_videoFormat isEqual:@"MOV"]) {
      _videoFormat = AVFileTypeQuickTimeMovie;
   }

   if (_session != nil) {
      _session.fileType = _videoFormat;
   }
}

- (void)changeMediaType:(NSString *)mediaType
{
   if ([mediaType isEqualToString:@"photo"]) {
      _recorder.captureSessionPreset = AVCaptureSessionPresetPhoto;
   } else {
      _recorder.captureSessionPreset = [SCRecorderTools bestCaptureSessionPresetCompatibleWithAllDevices];
   }
}

#pragma mark - Private Methods

- (NSString*)saveImage:(UIImage*)image
{
   NSString *name = [[NSProcessInfo processInfo] globallyUniqueString];
   name = [name stringByAppendingString:@".jpeg"];
   NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:name];

   if ([_device isEqual:@"front"]) {
      image = [UIImage imageWithCGImage:image.CGImage
                                  scale:image.scale
                            orientation:UIImageOrientationLeftMirrored];
   }

   [UIImageJPEGRepresentation(image, 1.0) writeToFile:filePath atomically:YES];

   return filePath;
}

#pragma mark - Public Methods

- (void)record
{
   [_recorder record];
}

- (void)capture:(void(^)(NSError *error, NSString *url))callback
{
   [_recorder capturePhoto:^(NSError *error, UIImage *image) {
      NSString *imgPath = [self saveImage:image];
      callback(error, imgPath);
   }];
}

- (void)pause:(void(^)())completionHandler
{
   [_recorder pause:completionHandler];
}

- (SCRecordSessionSegment*)lastSegment
{
   return [_session.segments lastObject];
}

- (void)removeLastSegment
{
   [_session removeLastSegment];
}

- (void)removeAllSegments
{
   [_session removeAllSegments:true];
}

- (void)turnOffFlash
{
   _recorder.flashMode = SCFlashModeOff;
}

- (void)removeSegmentAtIndex:(NSInteger)index
{
   [_session removeSegmentAtIndex:index deleteFile:true];
}

- (void)save:(void(^)(NSError *error, NSURL *outputUrl))callback
{
   AVAsset *asset = _session.assetRepresentingSegments;
   SCAssetExportSession *assetExportSession = [[SCAssetExportSession alloc] initWithAsset:asset];

   assetExportSession.outputFileType = _videoFormat;
   assetExportSession.outputUrl = [_session outputUrl];
   assetExportSession.videoConfiguration.preset = _videoQuality;
   assetExportSession.audioConfiguration.preset = _audioQuality;

   [assetExportSession exportAsynchronouslyWithCompletionHandler: ^{
      callback(assetExportSession.error, assetExportSession.outputUrl);
   }];
}


#pragma mark - SCRecorder events

- (void)recorder:(SCRecorder *)recorder didInitializeAudioInSession:(SCRecordSession *)recordSession error:(NSError *)error {
   if (error == nil) {
      NSLog(@"Initialized audio in record session");
   } else {
      NSLog(@"Failed to initialize audio in record session: %@", error.localizedDescription);
   }
}

- (void)recorder:(SCRecorder *)recorder didInitializeVideoInSession:(SCRecordSession *)recordSession error:(NSError *)error {
   if (error == nil) {
      NSLog(@"Initialized video in record session");
   } else {
      NSLog(@"Failed to initialize video in record session: %@", error.localizedDescription);
   }
}

#pragma mark - React View Management


- (void)layoutSubviews
{
   [super layoutSubviews];

   if (_previewView == nil) {
      [[AVAudioSession sharedInstance] setActive:NO error:nil];
      [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionMixWithOthers|AVAudioSessionCategoryOptionDefaultToSpeaker error:nil];
      [[AVAudioSession sharedInstance] setMode:AVAudioSessionModeVideoRecording error:nil];
      [[AVAudioSession sharedInstance] setActive:YES error:nil];

      _previewView = [[UIView alloc] initWithFrame:self.bounds];
      _recorder.previewView = _previewView;
      [_previewView setBackgroundColor:[UIColor blackColor]];
      [self insertSubview:_previewView atIndex:0];

      _focusView = [[SCRecorderToolsView alloc] initWithFrame:_previewView.bounds];
      _focusView.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
      _focusView.outsideFocusTargetImage = [UIImage imageNamed:@"camera_focus_button"];
      _focusView.recorder = _recorder;
      [_previewView addSubview:_focusView];

      [_recorder startRunning];

      _session = [SCRecordSession recordSession];
      [self setVideoFormat:_videoFormat];
      _recorder.session = _session;
   }
}

- (void)insertReactSubview:(UIView *)view atIndex:(NSInteger)atIndex
{
   [self addSubview:view];
}

- (void)removeReactSubview:(UIView *)subview
{
   [subview removeFromSuperview];
}

- (void)removeFromSuperview
{
   [self turnOffFlash];
   [super removeFromSuperview];
}

- (void)orientationChanged:(NSNotification *)notification
{
   [_recorder previewViewFrameChanged];
}

@end
