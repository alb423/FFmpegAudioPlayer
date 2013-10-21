//
//  AudioPlayer.h
//  iFrameExtractor
//
//  Created by Liao KuoHsun on 13/4/19.
//
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AudioPacketQueue.h"
#include "libavformat/avformat.h"
#include "libavutil/opt.h"
#include "libswresample/swresample.h"

// An audio queue can use any number of buffers—your application specifies how many. A typical number is three.
#define NUM_BUFFERS 3
#define AVCODEC_MAX_AUDIO_FRAME_SIZE 192000

typedef enum eAACType {
    eAAC_UNDEFINED  = 0,
    eAAC_RAW        = 1,
    eAAC_ADTS       = 2,
    eAAC_LATM       = 3,
}eAACType;


@interface AudioPlayer : NSObject{
    
    enum eAudioStatus {
        eAudioRunning = 1,
        eAudioStop = 2
    };
    
    enum eAudioRecordingStatus {
        eRecordInit = 1,
        eRecordRecording = 2,
        eRecordStop = 3
    };
    
                             // 1
    AudioStreamBasicDescription   mDataFormat;                    // 2
    AudioQueueRef                 mQueue;                         // 3
    AudioQueueBufferRef           mBuffers[NUM_BUFFERS];       // 4
    AudioFileID                   mAudioFile;                     // 5
    UInt32                        bufferByteSize;                 // 6
    SInt64                        mCurrentPacket;                 // 7
    UInt32                        mNumPacketsToRead;              // 8
    AudioStreamPacketDescription  *mPacketDescs;                  // 9
    bool                          mIsRunning;                     // 10
    
    bool isFormatVBR;

    AVCodecContext   *aCodecCtx;
    AudioPacketQueue *audioPacketQueue;
    SwrContext       *pSwrCtx;
    
    long LastStartTime;
    
    // For audio recording
    AVFormatContext *pRecordingAudioFC;
    AVCodecContext  *pOutputCodecContext;
    bool   enableRecording;
    UInt32 vRecordingAudioStreamIdx;
    UInt32 vRecordingAudioFormat;
    UInt32 vRecordingStatus;
    UInt32 vAudioOutputFileSize;
    FILE * pAudioOutputFile;
    //NSMutableArray *pSampleQueue;
}

-(id)initAudio: (AudioPacketQueue *) audioQueue withCodecCtx:(AVCodecContext *) aCodecCtx;
- (int) Play;
- (void) Stop:(BOOL)bStopImmediatelly;
- (void) SetVolume:(float)vVolume;
-(void) decodeAudioFile: (NSString *) FilePathIn ToPCMFile:(NSString *) FilePathOut withCodecCtx: (AVCodecContext *)pAudioCodecCtx withFormat:(AVFormatContext *) pFormatCtx withStreamIdx :(int) audioStream;
-(int) getStatus;

-(int) putAVPacket: (AVPacket *) pkt;
-(int) getAVPacket :(AVPacket *) pkt;
-(void)freeAVPacket:(AVPacket *) pkt;
-(int) getSize;
- (void) RecordingStart:(NSString *)pRecordingFile;
- (void) RecordingStop;
- (void) RecordingSetAudioFormat:(int)vAudioFormat;
@property BOOL bIsADTSAAS;
//@property NSMutableArray *pSampleQueue;
@property eAACType vAACType;
@end
