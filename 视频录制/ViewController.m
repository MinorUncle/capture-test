//
//  ViewController.m
//  视频录制
//
//  Created by 未成年大叔 on 15/9/1.
//  Copyright (c) 2015年 未成年大叔. All rights reserved.
//

#import "ViewController.h"
#import "OpenGLView20.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
typedef void(^PropertyChangeBlock)(AVCaptureDevice *captureDevice);

@interface ViewController ()<AVCaptureFileOutputRecordingDelegate,AVCaptureVideoDataOutputSampleBufferDelegate>//视频文件输出代理

@property (strong,nonatomic) AVCaptureSession *captureSession;//负责输入和输出设备之间的数据传递
@property (strong,nonatomic) AVCaptureDeviceInput *captureDeviceInput;//负责从AVCaptureDevice获得输入数据
@property (strong,nonatomic) AVCaptureMovieFileOutput *captureMovieFileOutput;//视频输出流
@property (strong,nonatomic) AVCaptureVideoDataOutput *captureDataOutput;//视频输出流
@property (strong,nonatomic) AVAssetWriter* videoWriter ;//写文件AVAssetWriterInput
@property (strong,nonatomic) AVAssetWriterInput* videoWriterInput;//写文件
@property(strong ,nonatomic)AVAssetWriterInput* audioWriterInput;


@property (strong,nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;//相机拍摄预览图层
@property (strong,nonatomic)AVCaptureDevice *captureDevice;//相机拍摄预览图层

@property (assign,nonatomic) BOOL enableRotation;//是否允许旋转（注意在视频录制过程中禁止屏幕旋转）
@property (assign,nonatomic) CGRect *lastBounds;//旋转的前大小
@property (assign,nonatomic) UIBackgroundTaskIdentifier backgroundTaskIdentifier;//后台任务标识
@property (weak, nonatomic) IBOutlet UIView *viewContainer;
@property (weak, nonatomic) IBOutlet UIButton *takeButton;//拍照按钮
@property (weak, nonatomic) IBOutlet UIImageView *focusCursor; //聚焦光标
@property (weak, nonatomic) IBOutlet OpenGLView20 *playView;    ///播放view


@end

@implementation ViewController

#pragma mark - 控制器视图方法
- (void)viewDidLoad {
    [super viewDidLoad];
}

-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    //初始化会话
    _captureSession=[[AVCaptureSession alloc]init];
    if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {//设置分辨率
        _captureSession.sessionPreset=AVCaptureSessionPreset640x480;
    }
    [self initVideoAudioWriter];
    //获得输入设备
    self.captureDevice=[self getCameraDeviceWithPosition:AVCaptureDevicePositionBack];//取得后置摄像头
    if (!self.captureDevice) {
        NSLog(@"取得后置摄像头时出现问题.");
        return;
    }
    NSError* error;
    if([self.captureDevice lockForConfiguration:&error]){
        self.captureDevice.activeVideoMinFrameDuration = CMTimeMake(1, 20);
    }else{
        NSLog(@"error:%@",error.localizedDescription);
    }

    //添加一个音频输入设备
    AVCaptureDevice *audioCaptureDevice=[[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
    
    
    //根据输入设备初始化设备输入对象，用于获得输入数据
    _captureDeviceInput=[[AVCaptureDeviceInput alloc]initWithDevice:self.captureDevice error:&error];
    if (error) {
        NSLog(@"取得设备输入对象时出错，错误原因：%@",error.localizedDescription);
        return;
    }
    AVCaptureDeviceInput *audioCaptureDeviceInput=[[AVCaptureDeviceInput alloc]initWithDevice:audioCaptureDevice error:&error];
    if (error) {
        NSLog(@"取得设备输入对象时出错，错误原因：%@",error.localizedDescription);
        return;
    }
    //初始化设备输出对象，用于获得输出数据
    _captureMovieFileOutput = [[AVCaptureMovieFileOutput alloc]init];
    _captureDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    //将设备输入添加到会话中
    if ([_captureSession canAddInput:_captureDeviceInput]) {
        [_captureSession addInput:_captureDeviceInput];
        [_captureSession addInput:audioCaptureDeviceInput];
//        AVCaptureConnection *captureConnection=[_captureMovieFileOutput connectionWithMediaType:AVMediaTypeVideo];
//        if ([captureConnection isVideoStabilizationSupported ]) {
//            captureConnection.preferredVideoStabilizationMode=AVCaptureVideoStabilizationModeAuto;
//        }
    }
    
    //将设备输出添加到会话中
//    if ([_captureSession canAddOutput:_captureMovieFileOutput]) {
//        [_captureSession addOutput:_captureMovieFileOutput];
//    }
    
    if ([_captureSession canAddOutput:_captureDataOutput]) {
        [_captureSession addOutput:_captureDataOutput];
    }
    
    
    //创建视频预览层，用于实时展示摄像头状态
    _captureVideoPreviewLayer=[[AVCaptureVideoPreviewLayer alloc]initWithSession:self.captureSession];
    
    CALayer *layer=self.viewContainer.layer;
    layer.masksToBounds=YES;
    
    _captureVideoPreviewLayer.frame=layer.bounds;
    _captureVideoPreviewLayer.videoGravity=AVLayerVideoGravityResizeAspectFill;//填充模式
    //将视频预览层添加到界面中
    //[layer addSublayer:_captureVideoPreviewLayer];
    [layer insertSublayer:_captureVideoPreviewLayer below:self.focusCursor.layer];
    
    _enableRotation=YES;
    [self addNotificationToCaptureDevice:self.captureDevice];
    [self addGenstureRecognizer];
}

-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    [self.captureSession startRunning];
}

-(void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    [self.captureSession stopRunning];
}

-(BOOL)shouldAutorotate{
    return self.enableRotation;
}

////屏幕旋转时调整视频预览图层的方向
//-(void)willTransitionToTraitCollection:(UITraitCollection *)newCollection withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator{
//    [super willTransitionToTraitCollection:newCollection withTransitionCoordinator:coordinator];
////    NSLog(@"%i,%i",newCollection.verticalSizeClass,newCollection.horizontalSizeClass);
//    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
//    NSLog(@"%i",orientation);
//    AVCaptureConnection *captureConnection=[self.captureVideoPreviewLayer connection];
//    captureConnection.videoOrientation=orientation;
//
//}
//屏幕旋转时调整视频预览图层的方向
-(void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration{
    AVCaptureConnection *captureConnection=[self.captureVideoPreviewLayer connection];
    captureConnection.videoOrientation=(AVCaptureVideoOrientation)toInterfaceOrientation;
}
//旋转后重新设置大小
-(void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation{
    _captureVideoPreviewLayer.frame=self.viewContainer.bounds;
}

-(void)dealloc{
    [self removeNotification];
}
#pragma mark - UI方法
#pragma mark 视频录制
- (IBAction)takeButtonClick:(UIButton *)sender {
    //根据设备输出获得连接
    AVCaptureConnection *captureConnection=[self.captureMovieFileOutput connectionWithMediaType:AVMediaTypeVideo];
    //根据连接取得设备输出的数据
    if (![self.captureMovieFileOutput isRecording]) {
        [sender setTitle:@"停止录制" forState:UIControlStateNormal];
        self.enableRotation=NO;
        //如果支持多任务则则开始多任务
        if ([[UIDevice currentDevice] isMultitaskingSupported]) {
            self.backgroundTaskIdentifier=[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
        }
        //预览图层和视频方向保持一致
        captureConnection.videoOrientation=[self.captureVideoPreviewLayer connection].videoOrientation;
        NSString *outputFielPath=[NSTemporaryDirectory() stringByAppendingString:@"myMovie.mov"];
        NSLog(@"save path is :%@",outputFielPath);
        NSURL *fileUrl=[NSURL fileURLWithPath:outputFielPath];
//        [self.captureMovieFileOutput startRecordingToOutputFileURL:fileUrl recordingDelegate:self];
        NSArray* a = self.captureDataOutput.availableVideoCodecTypes;
        NSArray* b = self.captureDataOutput.availableVideoCVPixelFormatTypes;
        NSLog(@"%@", a);
        NSLog(@"%@", b);
        self.captureDataOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey:b[2]};
        [self.captureDataOutput setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    }
    else{
        
//        [self.captureMovieFileOutput stopRecording];//停止录制
        [sender setTitle:@"开始录制" forState:UIControlStateNormal];
    }
}
#pragma mark 切换前后摄像头
- (IBAction)toggleButtonClick:(UIButton *)sender {
    AVCaptureDevice *currentDevice=[self.captureDeviceInput device];
    AVCaptureDevicePosition currentPosition=[currentDevice position];
    [self removeNotificationFromCaptureDevice:currentDevice];
    AVCaptureDevice *toChangeDevice;
    AVCaptureDevicePosition toChangePosition=AVCaptureDevicePositionFront;
    if (currentPosition==AVCaptureDevicePositionUnspecified||currentPosition==AVCaptureDevicePositionFront) {
        toChangePosition=AVCaptureDevicePositionBack;
    }
    toChangeDevice=[self getCameraDeviceWithPosition:toChangePosition];
    [self addNotificationToCaptureDevice:toChangeDevice];
    //获得要调整的设备输入对象
    AVCaptureDeviceInput *toChangeDeviceInput=[[AVCaptureDeviceInput alloc]initWithDevice:toChangeDevice error:nil];
    
    //改变会话的配置前一定要先开启配置，配置完成后提交配置改变
    [self.captureSession beginConfiguration];
    //移除原有输入对象
    [self.captureSession removeInput:self.captureDeviceInput];
    //添加新的输入对象
    if ([self.captureSession canAddInput:toChangeDeviceInput]) {
        [self.captureSession addInput:toChangeDeviceInput];
        self.captureDeviceInput=toChangeDeviceInput;
    }
    //提交会话配置
    [self.captureSession commitConfiguration];
    
}

#pragma mark - 视频输出代理
-(void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections{
    NSLog(@"开始录制...");
}
-(void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error{
    NSLog(@"视频录制完成.");
    //视频录入完成之后在后台将视频存储到相簿
    self.enableRotation=YES;
    [self saveToAlbum:outputFileURL];
    
}

-(BOOL)saveToAlbum:(NSURL*)outputFileURL{
    UIBackgroundTaskIdentifier lastBackgroundTaskIdentifier=self.backgroundTaskIdentifier;
    self.backgroundTaskIdentifier=UIBackgroundTaskInvalid;
    ALAssetsLibrary *assetsLibrary=[[ALAssetsLibrary alloc]init];
   __block BOOL flg;
    [assetsLibrary writeVideoAtPathToSavedPhotosAlbum:outputFileURL completionBlock:^(NSURL *assetURL, NSError *error) {
        if (error) {
            NSLog(@"保存视频到相簿过程中发生错误，错误信息：%@",error.localizedDescription);
            flg = NO;
        }
        if (lastBackgroundTaskIdentifier!=UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:lastBackgroundTaskIdentifier];
        }
        NSLog(@"成功保存视频到相簿.");
        flg = YES;
    }];
    return flg;

}

#pragma mark - 通知
/**
 *  给输入设备添加通知
 */
-(void)addNotificationToCaptureDevice:(AVCaptureDevice *)captureDevice{
    //注意添加区域改变捕获通知必须首先设置设备允许捕获
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        captureDevice.subjectAreaChangeMonitoringEnabled=YES;
    }];
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    //捕获区域发生改变
    [notificationCenter addObserver:self selector:@selector(areaChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}
-(void)printCMTime:(CMTime)time flg:(NSString*)str{
    NSLog(@"flg:%@    value:%lld    timescale:%d   sec:%f 秒",str,time.value,time.timescale,(time.value * 0.1)/time.timescale);
}
////收到buffer
bool i = false;
-(void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
//    CMSampleTimingInfo info;
//    CMSampleTimingInfo infoArry[7];
//    
//    CMItemCount count;
//    OSStatus status =  CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &info);
//    OSStatus status1 = CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, 1, infoArry, &count);
//    CMItemCount c =CMSampleBufferGetNumSamples(sampleBuffer);
    
    
    CMTime durationTime = CMSampleBufferGetDuration(sampleBuffer);
    CMTime presentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CMTime decodeTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    [self printCMTime:durationTime flg:@"duration"];
    [self printCMTime:decodeTime flg:@"decode"];
    [self printCMTime:presentTime  flg:@"present"];
//    
//    CVImageBufferRef  imgData = CMSampleBufferGetImageBuffer(sampleBuffer);
//    
//    
//    CVPixelBufferLockBaseAddress(imgData, 0);
//    void* p = CVPixelBufferGetBaseAddress(imgData);
//    size_t height = CVPixelBufferGetHeight(imgData);
//    size_t width = CVPixelBufferGetWidth(imgData);
//    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imgData);
//    
//    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
//    if (false) {
//        i = true;
//        return;
//    }
//    CGImageRef img = CGImageCreate(width, height, 8, 32, bytesPerRow, colorSpace, kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little, p, NULL, true, kCGRenderingIntentDefault);
//    
//    dispatch_async(dispatch_get_main_queue(), ^{
//        self.playView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageWithCGImage:img]];
//        CGImageRelease(img);
//    });
//    CGColorSpaceRelease(colorSpace);



//    if (status == noErr) {
//        [self printCMTime:info.duration flg:@"duration"];
//        [self printCMTime:info.decodeTimeStamp flg:@"decode"];
//        [self printCMTime:info.presentationTimeStamp  flg:@"present"];
//    }
//    if (status1 == noErr) {
//        for (int i = 0; i<7; i++) {
//            [self printCMTime:infoArry[i].duration flg:@"duration"];
//            [self printCMTime:infoArry[i].decodeTimeStamp flg:@"decode"];
//            [self printCMTime:infoArry[i].presentationTimeStamp  flg:@"present"];
//
//        }
//    }


    
//    CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, <#CMItemCount timingArrayEntries#>, <#CMSampleTimingInfo * _Nullable timingArrayOut#>, <#CMItemCount * _Nullable timingArrayEntriesNeededOut#>)
    //CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);

//    static int frame = 0;
//    CMTime lastSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
//    if( frame == 0 && _videoWriter.status != AVAssetWriterStatusWriting  ){
//        [_videoWriter startWriting];
//        [_videoWriter startSessionAtSourceTime:lastSampleTime];
//    }
//    if (captureOutput == _captureDataOutput){
//        if( _videoWriter.status > AVAssetWriterStatusWriting ){
//            NSLog(@"Warning: writer status is %ld", _videoWriter.status);
//            if( _videoWriter.status == AVAssetWriterStatusFailed )
//                NSLog(@"Error: %@", _videoWriter.error);
//            return;
//        }
//        if ([_videoWriterInput isReadyForMoreMediaData]){
//            if( ![_videoWriterInput appendSampleBuffer:sampleBuffer] ){
//                NSLog(@"Unable to write to video input");
//            }else{
//                NSLog(@"already write vidio");
//            }
//        }
//    }
    

//else if (captureOutput == audioOutput)
//
//{
//    
//    if( videoWriter.status > AVAssetWriterStatusWriting ) {
//        NSLog(@"Warning: writer status is %d", videoWriter.status);
//        if( videoWriter.status == AVAssetWriterStatusFailed )
//            NSLog(@"Error: %@", videoWriter.error);
//        return;
//    }
//    if ([audioWriterInput isReadyForMoreMediaData])
//        if( ![audioWriterInput appendSampleBuffer:sampleBuffer] )
//            NSLog(@"Unable to write to audio input");
//        else
//            NSLog(@"already write audio");
//}
//if (frame == FrameCount)
//{
//    [self closeVideoWriter];
//}
//frame ++;
}

-(void) initVideoAudioWriter

{
    CGSize size = CGSizeMake(480, 320);
    NSString *betaCompressionDirectory = [NSHomeDirectory()stringByAppendingPathComponent:@"Documents/Movie.mp4"];
    NSError *error = nil;
    unlink([betaCompressionDirectory UTF8String]);
    //----initialize compression engine
    self.videoWriter = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:betaCompressionDirectory]
                        
                                                 fileType:AVFileTypeQuickTimeMovie
                        
                                                    error:&error];
    
    NSParameterAssert(_videoWriter);
    if(error)NSLog(@"error = %@", [error localizedDescription]);
    NSDictionary *videoCompressionProps = [NSDictionary dictionaryWithObjectsAndKeys:
                                           [NSNumber numberWithDouble:128.0*1024.0],AVVideoAverageBitRateKey,
                                           nil ];
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:AVVideoCodecH264, AVVideoCodecKey,
                                   [NSNumber numberWithInt:size.width], AVVideoWidthKey,
                                   [NSNumber numberWithInt:size.height],AVVideoHeightKey,videoCompressionProps, AVVideoCompressionPropertiesKey, nil];
    
    self.videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    NSParameterAssert(_videoWriterInput);
    
    
    
    _videoWriterInput.expectsMediaDataInRealTime = YES;
    
    
    
    NSDictionary *sourcePixelBufferAttributesDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                                           
                                                           [NSNumber numberWithInt:kCVPixelFormatType_32ARGB], kCVPixelBufferPixelFormatTypeKey, nil];
    
    
    
    [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoWriterInput sourcePixelBufferAttributes:sourcePixelBufferAttributesDictionary];
    
    NSParameterAssert(_videoWriterInput);
    
    NSParameterAssert([_videoWriter canAddInput:_videoWriterInput]);
    
    
    
    if ([_videoWriter canAddInput:_videoWriterInput])
        
        NSLog(@"I can add this input");
    
    else
        
        NSLog(@"i can't add this input");
    
    
    
    // Add the audio input
    
    AudioChannelLayout acl;
    
    bzero( &acl, sizeof(acl));
    
    acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
    NSDictionary* audioOutputSettings = nil;
    
    //    audioOutputSettings = [ NSDictionary dictionaryWithObjectsAndKeys:
    
    //                           [ NSNumber numberWithInt: kAudioFormatAppleLossless ], AVFormatIDKey,
    
    //                           [ NSNumber numberWithInt: 16 ], AVEncoderBitDepthHintKey,
    
    //                           [ NSNumber numberWithFloat: 44100.0 ], AVSampleRateKey,
    
    //                           [ NSNumber numberWithInt: 1 ], AVNumberOfChannelsKey,
    
    //                           [ NSData dataWithBytes: &acl length: sizeof( acl ) ], AVChannelLayoutKey,
    
    //                           nil ];
    
    audioOutputSettings = [ NSDictionary dictionaryWithObjectsAndKeys:
                           
                           [ NSNumber numberWithInt: kAudioFormatMPEG4AAC ], AVFormatIDKey,
                           
                           [ NSNumber numberWithInt:64000], AVEncoderBitRateKey,
                           
                           [ NSNumber numberWithFloat: 44100.0 ], AVSampleRateKey,
                           
                           [ NSNumber numberWithInt: 1 ], AVNumberOfChannelsKey,                                      
                           
                           [ NSData dataWithBytes: &acl length: sizeof( acl ) ], AVChannelLayoutKey,
                           
                           nil ];
    
    
    _audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType: AVMediaTypeAudio outputSettings: audioOutputSettings ];
    
    
    
    _audioWriterInput.expectsMediaDataInRealTime = YES;
    
    // add input
    
    [_videoWriter addInput:_audioWriterInput];
    
    [_videoWriter addInput:_videoWriterInput];
    
}

-(void)removeNotificationFromCaptureDevice:(AVCaptureDevice *)captureDevice{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}
/**
 *  移除所有通知
 */
-(void)removeNotification{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self];
}

-(void)addNotificationToCaptureSession:(AVCaptureSession *)captureSession{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    //会话出错
    [notificationCenter addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:captureSession];
}



/**
 *  设备连接成功
 *
 *  @param notification 通知对象
 */
-(void)deviceConnected:(NSNotification *)notification{
    NSLog(@"设备已连接...");
}
/**
 *  设备连接断开
 *
 *  @param notification 通知对象
 */
-(void)deviceDisconnected:(NSNotification *)notification{
    NSLog(@"设备已断开.");
}
/**
 *  捕获区域改变
 *
 *  @param notification 通知对象
 */
-(void)areaChange:(NSNotification *)notification{
    NSLog(@"捕获区域改变...");
}

/**
 *  会话出错
 *
 *  @param notification 通知对象
 */
-(void)sessionRuntimeError:(NSNotification *)notification{
    NSLog(@"会话发生错误.");
}

#pragma mark - 私有方法

/**
 *  取得指定位置的摄像头
 *
 *  @param position 摄像头位置
 *
 *  @return 摄像头设备
 */
-(AVCaptureDevice *)getCameraDeviceWithPosition:(AVCaptureDevicePosition )position{
    NSArray *cameras= [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *camera in cameras) {
        if ([camera position]==position) {
            return camera;
        }
    }
    return nil;
}

/**
 *  改变设备属性的统一操作方法
 *
 *  @param propertyChange 属性改变操作
 */
-(void)changeDeviceProperty:(PropertyChangeBlock)propertyChange{
    AVCaptureDevice *captureDevice= [self.captureDeviceInput device];
    NSError *error;
    //注意改变设备属性前一定要首先调用lockForConfiguration:调用完之后使用unlockForConfiguration方法解锁
    if ([captureDevice lockForConfiguration:&error]) {
        propertyChange(captureDevice);
        [captureDevice unlockForConfiguration];
    }else{
        NSLog(@"设置设备属性过程发生错误，错误信息：%@",error.localizedDescription);
    }
}

/**
 *  设置闪光灯模式
 *
 *  @param flashMode 闪光灯模式
 */
-(void)setFlashMode:(AVCaptureFlashMode )flashMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFlashModeSupported:flashMode]) {
            [captureDevice setFlashMode:flashMode];
        }
    }];
}
/**
 *  设置聚焦模式
 *
 *  @param focusMode 聚焦模式
 */
-(void)setFocusMode:(AVCaptureFocusMode )focusMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:focusMode];
        }
    }];
}
/**
 *  设置曝光模式
 *
 *  @param exposureMode 曝光模式
 */
-(void)setExposureMode:(AVCaptureExposureMode)exposureMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:exposureMode];
        }
    }];
}
/**
 *  设置聚焦点
 *
 *  @param point 聚焦点
 */
-(void)focusWithMode:(AVCaptureFocusMode)focusMode exposureMode:(AVCaptureExposureMode)exposureMode atPoint:(CGPoint)point{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
        }
        if ([captureDevice isFocusPointOfInterestSupported]) {
            [captureDevice setFocusPointOfInterest:point];
        }
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:AVCaptureExposureModeAutoExpose];
        }
        if ([captureDevice isExposurePointOfInterestSupported]) {
            [captureDevice setExposurePointOfInterest:point];
        }
    }];
}

/**
 *  添加点按手势，点按时聚焦
 */
-(void)addGenstureRecognizer{
    UITapGestureRecognizer *tapGesture=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapScreen:)];
    [self.viewContainer addGestureRecognizer:tapGesture];
}
-(void)tapScreen:(UITapGestureRecognizer *)tapGesture{
    CGPoint point= [tapGesture locationInView:self.viewContainer];
    //将UI坐标转化为摄像头坐标
    CGPoint cameraPoint= [self.captureVideoPreviewLayer captureDevicePointOfInterestForPoint:point];
    [self setFocusCursorWithPoint:point];
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposureMode:AVCaptureExposureModeAutoExpose atPoint:cameraPoint];
}

/**
 *  设置聚焦光标位置
 *
 *  @param point 光标位置
 */
-(void)setFocusCursorWithPoint:(CGPoint)point{
    self.focusCursor.center=point;
    self.focusCursor.transform=CGAffineTransformMakeScale(1.5, 1.5);
    self.focusCursor.alpha=1.0;
    [UIView animateWithDuration:1.0 animations:^{
        self.focusCursor.transform=CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        self.focusCursor.alpha=0;
        
    }];
}
@end