//
//  PlayAudio.m
//  iFrameExtractor
//
//  Created by Liao KuoHsun on 13/4/19.
//
//
#import "AVFoundation/AVAudioSession.h"
#import "AudioPlayer.h"
#import "ViewController.h"
#import "AudioUtilities.h"

@implementation AudioPlayer

#define AUDIO_BUFFER_SECONDS 1
#define AUDIO_BUFFER_QUANTITY 3
#define DECODE_AUDIO_BY_FFMPEG 1

// TODO: how to know the correct setting of AudioStreamBasicDescription from ffmpeg info??
// 1. Remote AAC (BlackBerry.mp4)
//    can be decoded by FFMPEG(ok) or APPLE Hardware (ok)

// 2. Local AAC (AAC_12khz_Mono_5.aac)
//    can be decoded by FFMPEG (ok), by APPLE Hardware (ok).
//    We should remove ADTS header before copy data to Apple Audio Queue Services
//    After remove ADTS header, many aac from rstp can be rendered correctly.

// 3. Local PCM (PCM_MULAW) (test_mono_8000Hz_8bit_PCM.wav)
//    can be decoded by FFMPEG (ok) or APPLE Hardware (ok)

// 4. Remote PCM (should ok) need test??

//@synthesize pSampleQueue;
@synthesize bIsADTSAAS;


-(int) putAVPacket: (AVPacket *) pkt
{
    return [audioPacketQueue putAVPacket:pkt];
}

-(int) getAVPacket :(AVPacket *) pkt
{
    return  [audioPacketQueue getAVPacket:pkt];
}

-(void)freeAVPacket:(AVPacket *) pkt
{
    [audioPacketQueue freeAVPacket:pkt];
}

void HandleOutputBuffer (
                                void                 *aqData,                 // 1
                                AudioQueueRef        inAQ,                    // 2
                                AudioQueueBufferRef  inBuffer                 // 3
                                ){
    AudioPlayer* player=(__bridge AudioPlayer *)aqData;
    [player putAVPacketsIntoAudioQueue:inBuffer];
}


-(UInt32)putAVPacketsIntoAudioQueue:(AudioQueueBufferRef)audioQueueBuffer{
    AudioTimeStamp bufferStartTime={0};
    AVPacket AudioPacket={0};
    static int vSlienceCount=0;
    
    AudioQueueBufferRef buffer=audioQueueBuffer;
    
    av_init_packet(&AudioPacket);    
    buffer->mAudioDataByteSize = 0;
    buffer->mPacketDescriptionCount = 0;

    if(mIsRunning==false)
    {
        return 0 ;
    }
    
    // TODO: remove debug log
    //NSLog(@"get 1 from audioPacketQueue: %d", [audioPacketQueue count]);
    
    // If no data, we put silence audio (PCM format only)
    // If AudioQueue buffer is empty, AudioQueue will stop. 
    if([audioPacketQueue count]==0)
    {
        int err, vSilenceDataSize = 1024*64;
#if 0
        if(vSlienceCount>10)
        {
            // Stop fill silence, since the data may be eof or error happen
            //[self Stop:false];
            mIsRunning = false;
            return 0;
        }
#endif
        vSlienceCount++;
        NSLog(@"Put Silence -- Need adjust circular buffer");
        @synchronized(self)
        {
            // 20130427 set silence data to real silence
            memset(buffer->mAudioData,0,vSilenceDataSize);
            buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
            buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = vSilenceDataSize;
            buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket = 1;
            buffer->mAudioDataByteSize += vSilenceDataSize;
            buffer->mPacketDescriptionCount++;
        }
        
        if ((err = AudioQueueEnqueueBuffer(mQueue,
                                           buffer,
                                           0,
                                           NULL)))
        {
            NSLog(@"Error enqueuing audio buffer: %d", err);
        }

        return 1;
    }
    vSlienceCount = 0;
    
    
//    while (([audioPacketQueue count]>0) && (buffer->mPacketDescriptionCount < buffer->mPacketDescriptionCapacity))
    if(buffer->mPacketDescriptionCount < buffer->mPacketDescriptionCapacity)
    {
        
        [audioPacketQueue getAVPacket: &AudioPacket];
        
#if DECODE_AUDIO_BY_FFMPEG == 1 // decode by FFmpeg
        
        if (buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= AudioPacket.size)
        {
            uint8_t *pktData=NULL;
            int gotFrame = 0;            
            int pktSize;
            int len=0;
            AVCodecContext   *pAudioCodecCtx = aCodecCtx;
            AVFrame *pAVFrame1 = pAudioFrame;
            pktData=AudioPacket.data;
            pktSize=AudioPacket.size;
                      
            while(pktSize>0)
            {
                avcodec_get_frame_defaults(pAVFrame1);
                @synchronized(self)
                {
                    len = avcodec_decode_audio4(pAudioCodecCtx, pAVFrame1, &gotFrame, &AudioPacket);
                }
                if(len<0){
                    gotFrame = 0;
                    printf("Error while decoding\n");
                    break;
                }
                if(gotFrame>0) {
                    int outCount=0;
                    
                    // For broadcast, av_samples_get_buffer_size() may get incorrect size
                    // pAVFrame1->nb_samples may incorrect, too large;
                    int data_size = av_samples_get_buffer_size(pAVFrame1->linesize, pAudioCodecCtx->channels,
                                                               pAVFrame1->nb_samples,AV_SAMPLE_FMT_S16, 0);

                    if (buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= data_size)
                    {
                        @synchronized(self)
                        {
                            {
                                //uint8_t pTemp[8][data_size];
                                uint8_t pTemp[data_size];
                                uint8_t *pOut = (uint8_t *)&pTemp;
                                int in_samples = pAVFrame1->nb_samples;
                                //if (buffer->mPacketDescriptionCount == 0)
                                {
                                    bufferStartTime.mSampleTime = LastStartTime+in_samples;
                                    bufferStartTime.mFlags = kAudioTimeStampSampleTimeValid;
                                    LastStartTime = bufferStartTime.mSampleTime;
                                }
                                
                                outCount = swr_convert(pSwrCtx,
                                                       (uint8_t **)(&pOut),
                                                       in_samples,
                                                       (const uint8_t **)pAVFrame1->extended_data,
                                                       in_samples);
                                //NSLog(@"in_samples=%d, data_size=%d, outCount=%d", in_samples, data_size, outCount);
                                if(outCount<0)
                                    NSLog(@"swr_convert fail");
                                
                                memcpy((uint8_t *)buffer->mAudioData + buffer->mAudioDataByteSize, pOut, data_size);
                                buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
                                buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = data_size;
                                buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket
                                = 1;
                            
                                buffer->mAudioDataByteSize += data_size;
                                
                                if(vRecordingStatus==eRecordRecording)
                                {
                                    if(pAudioOutputFile!=NULL)
                                    {
                                        if(vRecordingAudioFormat==kAudioFormatMPEG4AAC)
                                        {
                                            ;
                                        }
                                        else
                                        {
                                            // WAVE file
                                            fwrite(pOut,  1, data_size, pAudioOutputFile);
                                            vAudioOutputFileSize += data_size;
                                        }
                                    }
                                }
                                //20130424
                                // waveform
                                //                                1. Compute and cache a reduction, by extracting maxima/minima from blocks of (say) 256 samples.
                                //                                2. Render this data by drawing a vertical line between each max/min pair.
                                //                                3. Clip the drawing to the damaged region wherever possible.
                                
                                //                                int vTmp=0, vSample=0;
                                //                                for(int j=0;j<in_samples;j+=2)
                                //                                {
                                //                                    vTmp += pTemp[0][j]<<8+pTemp[0][j+1];
                                //                                }
                                //                                vTmp = vTmp/in_samples;
                                //                                
                                //                                NSMutableData *pTmpData = [[NSMutableData alloc] initWithBytes:&vTmp length:sizeof(int)];
                                //                                [pSampleQueue addObject: pTmpData];
                            };
                        }
                        buffer->mPacketDescriptionCount++;
                    }
                    gotFrame = 0;
                }
                pktSize-=len;
                pktData+=len;
            }
        }
                
#else

        if (buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= AudioPacket.size)
        {
            int vOffsetOfADTS=0;
            uint8_t *pHeader = &(AudioPacket.data[0]);
            
            // 20130603
            // Parse audio data to see if there is ADTS header
            tAACADTSHeaderInfo vxADTSHeader={0};
            bIsADTSAAS = [AudioUtilities parseAACADTSHeader:pHeader ToHeader:(tAACADTSHeaderInfo *) &vxADTSHeader];

            if(bIsADTSAAS)
            {
                // Remove ADTS Header
                vOffsetOfADTS = 7;
            }
            else
            {
                ; // do nothing
            }
            
            memcpy((uint8_t *)buffer->mAudioData + buffer->mAudioDataByteSize, AudioPacket.data + vOffsetOfADTS, AudioPacket.size - vOffsetOfADTS);
            buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
            buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = AudioPacket.size - vOffsetOfADTS;
            buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket = aCodecCtx->frame_size;
            buffer->mAudioDataByteSize += (AudioPacket.size-vOffsetOfADTS);
            buffer->mPacketDescriptionCount++;
        }
#endif
        
        [audioPacketQueue freeAVPacket:&AudioPacket];
    }
    
    if (buffer->mPacketDescriptionCount > 0) {
        int err;
        
#if 1  // CBR
        if ((err = AudioQueueEnqueueBuffer(mQueue,
                                           buffer,
                                           0,
                                           NULL)))
#else  // VBR
            if ((err = AudioQueueEnqueueBufferWithParameters(mQueue,
                                                             buffer,
                                                             0,
                                                             NULL,
                                                             0,
                                                             0,
                                                             0,
                                                             NULL,
                                                             &bufferStartTime,
                                                             NULL)))
#endif
            {
                NSLog(@"Error enqueuing audio buffer: %d", err);
            }
    }
    return 0;
}



-(id)initAudio: (AudioPacketQueue *) pInQueue withCodecCtx :(AVCodecContext *) pAudioCodecCtx{
    int i=0, audio_index = 1;
    int vBufferSize=0;    
    int err;
    
    // support audio play when screen is locked
    NSError *setCategoryErr = nil;
    NSError *activationErr  = nil;
    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayback error:&setCategoryErr];
    [[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
    
    //pSampleQueue = [[NSMutableArray alloc] init];
    if(pInQueue)
    {
        audioPacketQueue = pInQueue;
    }
    else
    {
        audioPacketQueue = [[AudioPacketQueue alloc]initQueue];
    }
    aCodecCtx = pAudioCodecCtx;
    pAudioFrame = avcodec_alloc_frame();
    
    if (audio_index >= 0)
    {
        AudioStreamBasicDescription audioFormat={0};
        audioFormat.mFormatID = -1;
        audioFormat.mSampleRate = pAudioCodecCtx->sample_rate;
        audioFormat.mFormatFlags = 0;
        switch (pAudioCodecCtx->codec_id) {
            case AV_CODEC_ID_WMAV1:
            case AV_CODEC_ID_WMAV2:
                audioFormat.mFormatID = kAudioFormatLinearPCM;
                break;
            case AV_CODEC_ID_MP3:
                audioFormat.mFormatID = kAudioFormatMPEGLayer3;
                break;
            case AV_CODEC_ID_AAC:
                audioFormat.mFormatID = kAudioFormatMPEG4AAC;
                audioFormat.mFormatFlags = kMPEG4Object_AAC_Main;
                break;
            case AV_CODEC_ID_PCM_ALAW:
                audioFormat.mFormatID = kAudioFormatALaw;
                break; 
            case AV_CODEC_ID_PCM_MULAW:
                audioFormat.mFormatID = kAudioFormatULaw;
                break;
            case AV_CODEC_ID_PCM_U8:
                audioFormat.mFormatID = kAudioFormatLinearPCM;
                break;
            default:
                NSLog(@"Error: audio format '%s' (%d) is not supported", pAudioCodecCtx->codec_name, pAudioCodecCtx->codec_id);
                audioFormat.mFormatID = kAudioFormatAC3;
                break;
        }
        
        if (audioFormat.mFormatID != -1)
        {
#if DECODE_AUDIO_BY_FFMPEG == 1
            audioFormat.mFormatID = kAudioFormatLinearPCM;            
            audioFormat.mFormatFlags = kAudioFormatFlagsCanonical;//kAudioFormatFlagIsBigEndian|kAudioFormatFlagIsAlignedHigh;
            audioFormat.mSampleRate = pAudioCodecCtx->sample_rate;
            audioFormat.mBitsPerChannel = 8*av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
            audioFormat.mChannelsPerFrame = pAudioCodecCtx->channels;
            audioFormat.mBytesPerFrame = pAudioCodecCtx->channels * av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
            audioFormat.mBytesPerPacket= pAudioCodecCtx->channels * av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
            audioFormat.mFramesPerPacket = 1;
            audioFormat.mReserved = 0;

            // The default audio data defined by APPLE is 16bits.
            // If we got 32 or 8, we should covert it to 16bits
            if(pAudioCodecCtx->sample_fmt==AV_SAMPLE_FMT_FLTP) 
            {
                // 20130531
                if(pAudioCodecCtx->channel_layout!=0)
                {
                    pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                                 pAudioCodecCtx->channel_layout,
                                                 AV_SAMPLE_FMT_S16,
                                                 pAudioCodecCtx->sample_rate,
                                                 pAudioCodecCtx->channel_layout,
                                                 AV_SAMPLE_FMT_FLTP,
                                                 pAudioCodecCtx->sample_rate,
                                                 0,
                                                 0);
                }
                else
                {
                    pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                             pAudioCodecCtx->channels+1,
                                            AV_SAMPLE_FMT_S16,
                                             pAudioCodecCtx->sample_rate,
                                             pAudioCodecCtx->channels+1, AV_SAMPLE_FMT_FLTP,
                                             pAudioCodecCtx->sample_rate,
                                             0,
                                             0);
                }
                NSLog(@"sample_rate=%d, channels=%d, channel_layout=%lld",pAudioCodecCtx->sample_rate, pAudioCodecCtx->channels, pAudioCodecCtx->channel_layout);
                
                if(swr_init(pSwrCtx)<0)
                {
                    NSLog(@"swr_init() for AV_SAMPLE_FMT_FLTP fail");
                    return nil;
                }
            }
            if(pAudioCodecCtx->sample_fmt==AV_SAMPLE_FMT_S16P)
            {
                pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                             pAudioCodecCtx->channel_layout,
                                             AV_SAMPLE_FMT_S16,
                                             pAudioCodecCtx->sample_rate,
                                             pAudioCodecCtx->channel_layout,
                                             AV_SAMPLE_FMT_S16P,
                                             pAudioCodecCtx->sample_rate,
                                             0,
                                             0);
                if(swr_init(pSwrCtx)<0)
                {
                    NSLog(@"swr_init() for AV_SAMPLE_FMT_S16P fail");
                    return nil;
                }
            }
            else if(pAudioCodecCtx->sample_fmt==AV_SAMPLE_FMT_U8)
            {                    
                pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                             1,//pAudioCodecCtx->channel_layout,
                                             AV_SAMPLE_FMT_S16,
                                             pAudioCodecCtx->sample_rate,
                                             1,//pAudioCodecCtx->channel_layout,
                                             AV_SAMPLE_FMT_U8,
                                             pAudioCodecCtx->sample_rate,
                                             0,
                                             0);
                if(swr_init(pSwrCtx)<0)
                {
                    NSLog(@"swr_init()  fail");
                    return nil;
                }
            }
            else
            {
                // do nothing now
                // S16 to S16
                ;
            }
            
#else
            if(audioFormat.mFormatID == kAudioFormatMPEG4AAC)
            {
                audioFormat.mBytesPerPacket = 0;
                audioFormat.mFramesPerPacket = pAudioCodecCtx->frame_size;
                audioFormat.mBytesPerFrame = 0;
                audioFormat.mChannelsPerFrame = pAudioCodecCtx->channels;
                audioFormat.mBitsPerChannel = pAudioCodecCtx->bits_per_coded_sample;
                audioFormat.mReserved = 0;
            }
            else if(audioFormat.mFormatID == kAudioFormatMPEGLayer3)
            {
                audioFormat.mBytesPerPacket = 0;
                audioFormat.mFramesPerPacket = pAudioCodecCtx->frame_size;
                audioFormat.mBytesPerFrame = 0;
                audioFormat.mChannelsPerFrame = pAudioCodecCtx->channels;
                audioFormat.mBitsPerChannel = pAudioCodecCtx->bits_per_coded_sample;
                audioFormat.mReserved = 0;
            }
            else if(audioFormat.mFormatID == kAudioFormatLinearPCM)
            {   
                // TODO: The flag should be assigned according different file type
                // Current setting is used for AV_CODEC_ID_PCM_U8
                if(pAudioCodecCtx->sample_fmt==AV_SAMPLE_FMT_U8)
                {
                    audioFormat.mFormatFlags = kAudioFormatFlagIsPacked;
                    audioFormat.mSampleRate = pAudioCodecCtx->sample_rate; // 12000
                    audioFormat.mBitsPerChannel = pAudioCodecCtx->bits_per_coded_sample; //8;//16;
                    audioFormat.mChannelsPerFrame = 1;//pAudioCodecCtx->channels;
                    audioFormat.mBytesPerFrame = 1;
                    audioFormat.mBytesPerPacket = 1;
                    audioFormat.mFramesPerPacket = 1;
                    audioFormat.mReserved = 0;
                }
                else if(pAudioCodecCtx->sample_fmt==AV_SAMPLE_FMT_S16)
                {
                    audioFormat.mFormatFlags = kAudioFormatFlagIsPacked;
                    audioFormat.mSampleRate = pAudioCodecCtx->sample_rate; // 12000
                    audioFormat.mBitsPerChannel = pAudioCodecCtx->bits_per_coded_sample; //8;//16;
                    audioFormat.mChannelsPerFrame = 1;
                    audioFormat.mBytesPerFrame = 2;
                    audioFormat.mBytesPerPacket = 2;
                    audioFormat.mFramesPerPacket = 1;
                    audioFormat.mReserved = 0;
                }
            }
            
#endif
            if ((err = AudioQueueNewOutput(&audioFormat, HandleOutputBuffer, (__bridge void *)(self), NULL, NULL, 0, &mQueue))!=noErr) {
                NSLog(@"Error creating audio output queue: %d", err);
            }
            else
            {
                
                // When I test, sometimes the data from network may loss information
                // Below 2 checks if for CHT ipcam only
                if(pAudioCodecCtx->bit_rate==0) {
                    pAudioCodecCtx->bit_rate=0x100000;//0x50000;
                }
#if 1
                if(pAudioCodecCtx->frame_size==0) {
                    pAudioCodecCtx->frame_size=1024;
                }
#endif
                vBufferSize = [self DeriveBufferSize:audioFormat withPacketSize:pAudioCodecCtx->bit_rate/8 withSeconds:AUDIO_BUFFER_SECONDS];
                
                for (i = 0; i < AUDIO_BUFFER_QUANTITY; i++)
                {
                    //NSLog(@"%d packet capacity, %d byte capacity", (int)(pAudioCodecCtx->sample_rate * AUDIO_BUFFER_SECONDS / pAudioCodecCtx->frame_size + 1), (int)vBufferSize);
                    

                    if ((err = AudioQueueAllocateBufferWithPacketDescriptions(mQueue, vBufferSize, 1, &mBuffers[i]))!=noErr) {
                        NSLog(@"Error: Could not allocate audio queue buffer: %d", err);
                        AudioQueueDispose(mQueue, YES);
                        break;
                      }
                    
                } // end of for loop
            }
        } // end of if (audioFormat.mFormatID != -1)
    }
    
    
    Float32 gain=1.0;
    AudioQueueSetParameter(mQueue, kAudioQueueParam_Volume, gain);
    
    return self;
}    
    

- (void) Play{
    OSStatus eErr=noErr;
    
    int i;

    mIsRunning = true;
    LastStartTime = 0;
    
    for(i=0;i<AUDIO_BUFFER_QUANTITY;i++)
    {
        [self putAVPacketsIntoAudioQueue:mBuffers[i]];
    }
    
    // 20130427 Test temparally    
    // Decodes enqueued buffers in preparation for playback
    
#if DECODE_AUDIO_BY_FFMPEG == 0
    eErr=AudioQueuePrime(mQueue, 0, NULL);
    if(eErr!=noErr)
    {
        NSLog(@"AudioQueuePrime() error %ld", eErr);
        //return;
    }
#endif
    
    //
    eErr=AudioQueueStart(mQueue, nil);
    if(eErr!=noErr)
    {
        NSLog(@"AudioQueueStart() error %ld", eErr);
    }
}

-(void)Stop:(BOOL)bStopImmediatelly{
    
    mIsRunning = false;

    AudioQueueStop(mQueue, bStopImmediatelly);
    
    // Disposing of the audio queue also disposes of all its resources, including its buffers.
    AudioQueueDispose(mQueue, bStopImmediatelly);
    
    if (pSwrCtx)   swr_free(&pSwrCtx);
    if (pAudioFrame)    avcodec_free_frame(&pAudioFrame);
    
    NSLog(@"Dispose Apple Audio Queue");
}


-(int) getStatus{
    if(mIsRunning==true)
        return eAudioRunning;
    else
        return eAudioStop;
}


// Reference "Audio Queue Services Programming Guide"
-(int) DeriveBufferSize:(AudioStreamBasicDescription) ASBDesc withPacketSize:(UInt32)  maxPacketSize
withSeconds:(Float64)    seconds
{
    static const int maxBufferSize = 0x50000;
    static const int minBufferSize = 0x4000; 
    int outBufferSize=0;
    
    if (ASBDesc.mFramesPerPacket != 0) {
        Float64 numPacketsForTime =
        ASBDesc.mSampleRate / ASBDesc.mFramesPerPacket * seconds;
        outBufferSize = numPacketsForTime * maxPacketSize;
    } else {
        outBufferSize =
        maxBufferSize > maxPacketSize ?
        maxBufferSize : maxPacketSize;
    }
    
    if (
        outBufferSize > maxBufferSize &&
        outBufferSize > maxPacketSize
        )
        outBufferSize = maxBufferSize;
    else {
        if (outBufferSize < minBufferSize)
            outBufferSize = minBufferSize;
    }
    
    return outBufferSize;
}

#pragma mark - Audio Recording
- (void) RecordingStart:(NSString *)pRecordingFile
{
    NSLog(@"RecordingStart");
    vRecordingStatus = eRecordInit;
    pAudioOutputFile=fopen([pRecordingFile UTF8String],"wb");
    if (pAudioOutputFile==NULL)
    {
        NSLog(@"Open file %@ error",pRecordingFile);
        return;
    }
    

    if(vRecordingAudioFormat==kAudioFormatMPEG4AAC)
    {
        ;
    }
    else
    {
        // Save as WAV file
        // Create the wave header
        [AudioUtilities writeWavHeaderWithCodecCtx: aCodecCtx withFormatCtx: nil toFile: pAudioOutputFile];
    }
    vRecordingStatus = eRecordRecording;
}

- (void) RecordingStop
{
    NSLog(@"RecordingStop");    
    vRecordingStatus = eRecordStop;
    
    if(vRecordingAudioFormat==kAudioFormatMPEG4AAC)
    {
        ;
    }
    else
    {
        // Default is WAV file (kAudioFormatLinearPCM)
        // Update the wave header
        fseek(pAudioOutputFile,40,SEEK_SET);
        fwrite(&vAudioOutputFileSize,1,sizeof(int32_t),pAudioOutputFile);
        vAudioOutputFileSize+=36;
        fseek(pAudioOutputFile,4,SEEK_SET);
        fwrite(&vAudioOutputFileSize,1,sizeof(int32_t),pAudioOutputFile);
        fclose(pAudioOutputFile);
    }
   
}

#pragma mark - Test tool of Audio
-(void) decodeAudioFile: (NSString *) FilePathIn ToPCMFile:(NSString *) FilePathOut withCodecCtx: (AVCodecContext *)pAudioCodecCtx withFormat:(AVFormatContext *) pFormatCtx withStreamIdx :(int) audioStream{
    // Test to write a audio file into PCM format file
    FILE *wavFile=NULL;
    AVPacket AudioPacket={0};
    AVFrame  *pAVFrame1;
    int iFrame=0;
    uint8_t *pktData=NULL;
    int pktSize, audioFileSize=0;
    int gotFrame=0;
    
    pAVFrame1 = avcodec_alloc_frame();
    av_init_packet(&AudioPacket);
    
    NSString *AbsPath = @"/Users/liaokuohsun/" ;
    AbsPath = [AbsPath stringByAppendingString:FilePathOut];
    wavFile=fopen([AbsPath UTF8String],"wb");
    //wavFile=fopen("//Users//liaokuohsun//myPlayerWav.wav","wb");
    if (wavFile==NULL)
    {
        printf("open file for writing error\n");
        return;
    }
    
    [AudioUtilities writeWavHeaderWithCodecCtx: pAudioCodecCtx withFormatCtx: pFormatCtx toFile:wavFile ];
    while(av_read_frame(pFormatCtx,&AudioPacket)>=0) {
        if(AudioPacket.stream_index==audioStream) {
            int len=0;
            if((iFrame++)>=4000)
                break;
            pktData=AudioPacket.data;
            pktSize=AudioPacket.size;
            while(pktSize>0) {
                len = avcodec_decode_audio4(pAudioCodecCtx, pAVFrame1, &gotFrame, &AudioPacket);
                if(len<0){
                    printf("Error while decoding\n");
                    break;
                }
                if(gotFrame>0) {
                    int data_size = av_samples_get_buffer_size(NULL, pAudioCodecCtx->channels,
                                                               pAVFrame1->nb_samples,pAudioCodecCtx->sample_fmt, 1);
                    fwrite(pAVFrame1->data[0], 1, data_size, wavFile);
                    
                    audioFileSize+=data_size;
                    fflush(wavFile);
                    gotFrame = 0;
                }
                pktSize-=len;
                pktData+=len;
            }
        }
        [audioPacketQueue freeAVPacket:&AudioPacket];
    }
    fseek(wavFile,40,SEEK_SET);
    fwrite(&audioFileSize,1,sizeof(int32_t),wavFile);
    audioFileSize+=36;
    fseek(wavFile,4,SEEK_SET);
    fwrite(&audioFileSize,1,sizeof(int32_t),wavFile);
    fclose(wavFile);
}

@end
