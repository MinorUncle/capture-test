//
//  H264Encoder.m
//  视频录制
//
//  Created by tongguan on 15/12/28.
//  Copyright © 2015年 未成年大叔. All rights reserved.
//

#import "H264Encoder.h"
@interface H264Encoder()
{
    

}
@property(nonatomic)VTCompressionSessionRef enCodeSession;
@end

@implementation H264Encoder
H264Encoder* encoder ;
- (instancetype)init
{
    self = [super init];
    if (self) {
        encoder = self;
        [self creatEnCodeSession];
    }
    return self;
}



//编码
-(void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    CVImageBufferRef imgRef = CMSampleBufferGetImageBuffer(sampleBuffer);
    OSStatus status = VTCompressionSessionEncodeFrame(
                                                  _enCodeSession,
                                                  imgRef,
                                                  kCMTimeInvalid,
                                                  kCMTimeInvalid, // may be kCMTimeInvalid
                                                  NULL,
                                                  NULL,
                                                  NULL );
    if (status != 0) {
        NSLog(@"encodeSampleBuffer error:%d",status);
        return;
    }
}

-(void)creatEnCodeSession{
    OSStatus t = VTCompressionSessionCreate(
                                            NULL,
                                            640,
                                            480,
                                            kCMVideoCodecType_H264,
                                            NULL,
                                            NULL,
                                            NULL,
                                            encodeOutputCallback,
                                            NULL,
                                            &_enCodeSession);
    NSLog(@"VTCompressionSessionCreate status:%d",(int)t);
    VTSessionSetProperty(_enCodeSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    
}

void encodeOutputCallback(void *  outputCallbackRefCon,void *  sourceFrameRefCon,OSStatus statu,VTEncodeInfoFlags infoFlags,
                          CMSampleBufferRef sample ){
    if (statu != 0) return;
    if (!CMSampleBufferDataIsReady(sample))
    {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    
    if (!CMSampleBufferDataIsReady(sample))
    {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }

    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sample, true), 0)), kCMSampleAttachmentKey_NotSync);
    NSMutableData* data = [[NSMutableData alloc]init];
    
    if (keyframe)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
        size_t sparameterSetSize, sparameterSetCount;
        int spHeadSize;
        int ppHeadSize;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, &spHeadSize );
        if (statusCode == noErr)
        {
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, &ppHeadSize );
            if (statusCode == noErr)
            {
                [data  appendBytes:"\x00\x00\x00\x01" length:4]; NSLog(@"data:%@",data);
                [data appendBytes:sparameterSet length:sparameterSetSize]; NSLog(@"data:%@",data);
                [data appendBytes:"\x00\x00\x00\x01" length:4]; NSLog(@"data:%@",data);
                [data appendBytes:pparameterSet length:pparameterSetSize];
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sample);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    

    if (statusCodeRet == noErr) {
        
        uint32_t bufferOffset = 0;
        static const uint32_t AVCCHeaderLength = 4;
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            
            // Read the NAL unit length
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            [data appendBytes:"\x00\x00\x00\x01" length:4];
            [data appendBytes:dataPointer + bufferOffset + AVCCHeaderLength length:NALUnitLength];
            NSMutableData* temData = data;
            
            uint8_t* frame = malloc(temData.length) ;
            
            [temData getBytes:frame length:temData.length];
            [encoder.deleagte encodeCompleteBuffer:frame withLenth:temData.length];
            
            data = [[NSMutableData alloc]init];
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
}


@end
