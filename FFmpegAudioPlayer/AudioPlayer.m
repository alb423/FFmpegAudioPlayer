//
//  PlayAudio.m
//  iFrameExtractor
//
//  Created by Liao KuoHsun on 13/4/19.
//
//
#import "AVFoundation/AVAudioSession.h"
#import "AudioPlayer.h"
#import "AudioUtilities.h"
#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "libavutil/common.h"


#if 0
#import "mydef.h" // for DECODE_AUDIO_BY_FFMPEG definition
#else
#import "ViewController.h"
#define DECODE_AUDIO_BY_FFMPEG 1//0
#endif

@implementation AudioPlayer
{
    NSTimer *vReConnectTimer;
}

#define AUDIO_LIVENESS_CHECK_TIMER 1  // Seconds
#define AUDIO_BUFFER_SECONDS 1
#define AUDIO_BUFFER_QUANTITY 3


// If we want to enable DECODE_AUDIO_BY_FFMPEG, we should set correct AVCodecContext
// For VSaaS project, we only need support 2 codec, ADTS AAC and PCMA.
// So DECODE_AUDIO_BY_FFMPEG is unnecessary
// #define DECODE_AUDIO_BY_FFMPEG 0


// Feartue list
// 1. We should enlarge the voice volume (ok)
// 2. How to know the correct setting of AudioStreamBasicDescription from ffmpeg info??
//    If the file is ADTS AAC, we can get them from ADTS header.
//    Otherwise, get them from RTSP SDP.


// =========== Test Sample =========== 
// 1. Remote AAC (BlackBerry.mp4)
//    can be decoded by FFMPEG(ok) or APPLE Hardware (ok)

// 2. Local AAC (AAC_12khz_Mono_5.aac)
//    can be decoded by FFMPEG (ok), by APPLE Hardware (ok).
//    We should remove ADTS header before copy data to Apple Audio Queue Services
//    After remove ADTS header, many aac from rstp can be rendered correctly.

// 3. Local PCM (PCM_MULAW) (test_mono_8000Hz_8bit_PCM.wav)
//    can be decoded by FFMPEG (ok) or APPLE Hardware (ok)

// 4. Remote PCM (PCM_ALAW) need test??
//    can be decoded by FFMPEG (ok) or APPLE Hardware (ok)


//@synthesize pSampleQueue;
@synthesize bIsADTSAAS;
@synthesize vAACType;

-(int) getSize
{
    return [audioPacketQueue size];
}

-(int) getCount
{
    return [audioPacketQueue count];
}

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

-(void)dealloc
{
    [audioPacketQueue destroyQueue];
    audioPacketQueue = nil;
}

// 20131101 albert.liao modified start
-(int)getAudioQueueRunningStatus
{
    OSStatus vRet = 0;
    UInt32 bFlag=0, vSize=sizeof(UInt32);
    vRet = AudioQueueGetProperty(mQueue,
                                 kAudioQueueProperty_IsRunning,
                                 &bFlag,
                                 &vSize);
    
    return bFlag;
}

-(void)reConnect2:(NSTimer *)timer {
    if(timer!=nil)
    {
        if([self getStatus]!=eAudioRunning)
        {
            if([self getCount]>5)
            {
                NSLog(@"func:%s line %d audio queue restart now",__func__, __LINE__);
                [timer invalidate];
                [self Play];
            }
        }
    }
}

-(void) restartAudioQueue
{
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        vReConnectTimer = [NSTimer scheduledTimerWithTimeInterval:AUDIO_LIVENESS_CHECK_TIMER
                                                           target:self
                                                         selector:@selector(reConnect2:)
                                                         userInfo:nil
                                                          repeats:YES];
    });
}

void CheckAudioQueueRunningStatus(void *inUserData,
                         AudioQueueRef           inAQ,
                         AudioQueuePropertyID    inID)
{
    AudioPlayer* player=(__bridge AudioPlayer *)inUserData;
    if(inID==kAudioQueueProperty_IsRunning)
    {
        UInt32 bFlag=0;
        bFlag = [player getAudioQueueRunningStatus];
        
        if(bFlag==0)
        {
            NSLog(@"AudioQueueRunningStatus : stop");
            if([player getStatus]!=eAudioStop)
            {
                NSLog(@"Try to restart Audio Queue");
                [player restartAudioQueue];
            }
        }
        else
        {
            NSLog(@"AudioQueueRunningStatus : start");
        }
    };
}


// 20131101 albert.liao modified end



void HandleOutputBuffer (
                                void                 *aqData,                 // 1
                                AudioQueueRef        inAQ,                    // 2
                                AudioQueueBufferRef  inBuffer                 // 3
                                ){
    if(aqData!=nil)
    {
        AudioPlayer* player=(__bridge AudioPlayer *)aqData;
        [player putAVPacketsIntoAudioQueue:inBuffer];
    }
}


-(UInt32)putAVPacketsIntoAudioQueue:(AudioQueueBufferRef)audioQueueBuffer{
    AudioTimeStamp bufferStartTime={0};
    AVPacket AudioPacket={0};
    static int vSlienceCount=0;
    
    AudioQueueBufferRef buffer=audioQueueBuffer;
    
    av_init_packet(&AudioPacket);    
    buffer->mAudioDataByteSize = 0;
    buffer->mPacketDescriptionCount = 0;

    if(AudioStatus==eAudioStop)
    {
        return 0 ;
    }
    
    // NSLog(@"get 1 from audioPacketQueue: %d", [audioPacketQueue count]);
    
    // If no data, we put silence audio (PCM format only)
    // If AudioQueue buffer is empty, AudioQueue will stop. 
    
    // 20130716
    // If AudioQueue is too small, it may be disconnected.
    // We should try to reconnect again 
    if([audioPacketQueue count]==0)
    {
        int err, vSilenceDataSize = 1024*16;
#if 1
        if(vSlienceCount>20)
        {
            // Stop fill silence, since the data may be eof or error happen
            //[self Stop:false];
            //AudioQueuePause(mQueue);
            AudioStatus = eAudioPause;
            NSLog(@"audioPacketQueue is empty for a long time!! restart it");
            AudioQueueStop(mQueue, true);
            return 1;
        }
#endif
        vSlienceCount++;
        NSLog(@"Put Silence -- Need adjust circular buffer");
        //@synchronized(self)
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
            int bRecording = 0;
            AVCodecContext   *pAudioCodecCtx = aCodecCtx;
            pktData=AudioPacket.data;
            pktSize=AudioPacket.size;
            
            //NSLog(@"pktSize = %d", pktSize);
            // Enable/Disable recording
            if(vRecordingStatus==eRecordRecording)
            {
                bRecording = 1;
            }
            
            while(pktSize>0)
            {
                AVFrame *pAVFrame1 = avcodec_alloc_frame();
                avcodec_get_frame_defaults(pAVFrame1);
                
                //@synchronized(self)
                {
                    len = avcodec_decode_audio4(pAudioCodecCtx, pAVFrame1, &gotFrame, &AudioPacket);
                //}
                if(len<0){
                    gotFrame = 0;
                    printf("Error while decoding\n");
                    return -1;
                }
                if(gotFrame>0) {
                    int outCount=0;
                    
                    // For broadcast (WMA), av_samples_get_buffer_size() may get incorrect size
                    // pAVFrame1->nb_samples may incorrect, too large;
                    int data_size = av_samples_get_buffer_size(pAVFrame1->linesize, pAudioCodecCtx->channels,
                                                               pAVFrame1->nb_samples,AV_SAMPLE_FMT_S16, 0);

                    if (buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= data_size)
                    {
                        //@synchronized(self)
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
                                
                                if(bRecording==1)
                                {
                                    if(vRecordingAudioFormat!=kAudioFormatLinearPCM)
                                    {
                                        if(aCodecCtx->codec_id==AV_CODEC_ID_AAC)
                                        {
                                            // no ffmpeg decodec
                                            
                                            uint8_t *pHeader = &(AudioPacket.data[0]);
                                            // Parse audio data to see if there is ADTS header
                                            tAACADTSHeaderInfo vxADTSHeader={0};
                                            bIsADTSAAS = [AudioUtilities parseAACADTSHeader:pHeader ToHeader:(tAACADTSHeaderInfo *) &vxADTSHeader];
                                    
                                            AVPacket Pkt={0};
                                            
                                            av_init_packet(&Pkt);
                                            
                                            if(bIsADTSAAS)
                                            {
                                                Pkt.size = AudioPacket.size-7;
                                                Pkt.data = AudioPacket.data+7;
                                            }
                                            else
                                            {
                                                // This will produce error message
                                                // "malformated aac bitstream, use -absf aac_adtstoasc"
                                                Pkt.size = AudioPacket.size;
                                                Pkt.data = AudioPacket.data;
                                            }
                                            //Pkt.stream_index = 1;//AudioPacket.stream_index;
                                            Pkt.flags |= AV_PKT_FLAG_KEY;
                                    

                                            if(pRecordingAudioFC)
                                                av_interleaved_write_frame( pRecordingAudioFC, &Pkt );
                                            else
                                                NSLog(@" %s:%d pRecordingAudioFC is NULL!!", __FILE__, __LINE__);
                                        }
                                        else
                                        {
                                            // This part can record ok
                                            int vRet=0;
                                            AVPacket Pkt={0};
                      
                                            // nb_samples =
                                            // buf_size * 8 / (avctx->channels * av_get_bits_per_sample(avctx->codec_id))
                                            // linesize[0] = nb_samples * pOutputCodecContext->Channels *av_get_bytes_per_sample(pOutputCodecContext->sample_fmt);
                                            
                                            // For my testing, linesize[0] = 4 * nb_samples
                                            // pOutputCodecContext->frame_size=1024
                                            // pAVFrame1->nb_samples is large then framesize, so encode will error
                                            // We need split AVFrame
#if 1
                                            // Test wit WMA ok
                                            // Reference:
                                            // http://ffmpeg.org/doxygen/0.6/output-example_8c-source.html
                                            static int64_t vInitPts=0, vInitDts=0;
                                            int64_t vSamples = 0, vSplitSamples = 0, vCopySize=0;
                                            int buf_size = 0, i=1 ,vBytesPerSample=0;

                                            
                                            vBytesPerSample = av_get_bytes_per_sample(pOutputCodecContext->sample_fmt);
                                            vSamples = pAVFrame1->nb_samples;
                                            
                                            
//                                            int vBufLen=0;
//                                            int8_t *pTmpBuffer = NULL;
//                                            vBufLen = pAVFrame1->nb_samples * vBytesPerSample * pOutputCodecContext->channels;
//                                            pTmpBuffer = malloc(vBufLen+1);
//                                            memset(pTmpBuffer, 0, vBufLen);
//                                            memcpy(pTmpBuffer, pAVFrame1->extended_data[0], vBufLen);
                                            
                                            NSLog(@"Save sample %lld, vBytesPerSample=%d, dts=%lld, %lld, %lld",vSamples, vBytesPerSample,pAVFrame1->pts, pAVFrame1->pkt_dts, pAVFrame1->pkt_pts);
                                            
//                                            if(vInitPts==0)
//                                            {
//                                                vInitPts = pAVFrame1->pkt_pts;
//                                            }
//                                            else
//                                            {
//                                                pAVFrame1->pkt_pts -= vInitPts ;
//                                            }
//                                            
//                                            if(vInitDts==0)
//                                            {
//                                                vInitDts = pAVFrame1->pkt_dts;
//                                            }
//                                            else
//                                            {
//                                                pAVFrame1->pkt_dts -= vInitDts ;
//                                            }

                                            NSLog(@"line:%d vSamples=%lld, frame_size=%d",__LINE__, vSamples, pOutputCodecContext->frame_size);
                                            
                                            while(vSamples - vSplitSamples > 0)
                                            {
                                                int gotFrame2=0;
                                                AVPacket Pkt2={0};
                                                AVFrame *pAVFrame2 = avcodec_alloc_frame();
                                                
                                                avcodec_get_frame_defaults(pAVFrame2);
                                                
                                                
                                                pAVFrame2->channel_layout = pAVFrame1->channel_layout;
                                                pAVFrame2->channels = pAVFrame1->channels;
                                                
                                                pAVFrame2->sample_rate = pAVFrame1->sample_rate;
                                                pAVFrame2->sample_aspect_ratio = pAVFrame1->sample_aspect_ratio;
                                                
                                                
                                                
                                                if(vSamples - vSplitSamples >= pOutputCodecContext->frame_size)
                                                {
                                                    NSLog(@"line:%d %d vSplitSamples=%lld",__LINE__, i++, vSplitSamples);

                                                    // split AVFrame to smaller frame
                                                    pAVFrame2->nb_samples = pOutputCodecContext->frame_size;
                                                    
                                                    //pAVFrame2->linesize[0] = pAVFrame1->linesize[0];
                                                    buf_size = pOutputCodecContext->frame_size  *vBytesPerSample* pOutputCodecContext->channels;
                                                    
                                                    // This function fills in frame->data, frame->extended_data, frame->linesize[0].
                                                    vRet = avcodec_fill_audio_frame(pAVFrame2, pAVFrame1->channels,pOutputCodecContext->sample_fmt, &pAVFrame1->extended_data[0][vCopySize], buf_size, 0);
                                                    if(vRet!=0)
                                                    {
                                                        NSLog(@"%d avcodec_fill_audio_frame() error %d", __LINE__, vRet);
                                                    }
                                                    vCopySize += buf_size;
                                                    vSplitSamples += pAVFrame2->nb_samples;
                                                    
                                                }
                                                else
                                                {
                                                    if(vSplitSamples!=0)
                                                    {
                                                        NSLog(@"line:%d %d vSplitSamples=%lld",__LINE__, i++, vSplitSamples);

                                                        pAVFrame2->nb_samples = vSamples - vSplitSamples;
                                                        
                                                        buf_size = pAVFrame2->nb_samples *vBytesPerSample * pOutputCodecContext->channels;
                                                        
                                                        vRet = avcodec_fill_audio_frame(pAVFrame2, pAVFrame1->channels,pOutputCodecContext->sample_fmt, &pAVFrame1->extended_data[0][vCopySize], buf_size, 0);
                                                        if(vRet!=0)
                                                        {
                                                            NSLog(@"%d avcodec_fill_audio_frame() error %d", __LINE__, vRet);
                                                        }
                                                        //vSplitSamples = vSamples;
                                                        vCopySize += buf_size;
                                                        vSplitSamples += pAVFrame2->nb_samples;
                                                    }
                                                    else
                                                    {
                                                        NSLog(@"line:%d %d vSplitSamples=%lld",__LINE__, i++, vSplitSamples);

                                                        //pAVFrame2->linesize[0] = pAVFrame2->linesize[0];

                                                        buf_size = vSamples * vBytesPerSample *pOutputCodecContext->channels;
                                                        
                                                        vRet = avcodec_fill_audio_frame(pAVFrame2, pAVFrame1->channels,pOutputCodecContext->sample_fmt, &pAVFrame1->data[0][0], buf_size, 0);
                                                        if(vRet!=0)
                                                        {
                                                            NSLog(@"%d avcodec_fill_audio_frame() error %d", __LINE__, vRet);
                                                        }
                                                        //vSplitSamples = vSamples;
                                                        vSplitSamples += pAVFrame2->nb_samples;

                                                    }
                                                }
                                                
                                                //av_new_packet(&Pkt2, pAVFrame2->nb_samples);
                                                av_init_packet(&Pkt2);
                                                
                                                vRet = avcodec_encode_audio2(pOutputCodecContext, &Pkt2, pAVFrame2, &gotFrame2);
                                                if(vRet==0)
                                                {
                                                    if(gotFrame2>0)
                                                    {
                                                        Pkt2.flags |= AV_PKT_FLAG_KEY;
                                                        vRet = av_interleaved_write_frame( pRecordingAudioFC, &Pkt2 );
                                                        if(vRet!=0)
                                                        {
                                                            NSLog(@"write frame error %s", av_err2str(vRet));
                                                        }
                                                    }
                                                    else
                                                    {
                                                        NSLog(@"gotFrame %d", gotFrame2);
                                                    }
                                                }
                                                else
                                                {
                                                    char pErrBuf[1024];
                                                    int  vErrBufLen = sizeof(pErrBuf);
                                                    av_strerror(vRet, pErrBuf, vErrBufLen);
                                                    
                                                    NSLog(@"vRet=%d, Err=%s",vRet,pErrBuf);
                                                    NSLog(@"data_size=%d,framesize=%d",data_size, pOutputCodecContext->frame_size);
                                                    NSLog(@"linesize=%d channels=%d", pAVFrame1->linesize[0], pAudioCodecCtx->channels);
                                                    NSLog(@"nb_samples=%d, sample_rate=%d",pAVFrame1->nb_samples,pAVFrame1->sample_rate);
                                                    
                                                }
                                                
                                                av_free_packet(&Pkt2);
                                                if(pAVFrame2) avcodec_free_frame(&pAVFrame2);
                                                
                                            }
                                            
                                            
#else
                                            // Test with AAC ok
                                            vRet = avcodec_encode_audio2(pOutputCodecContext, &Pkt, pAVFrame1, &gotFrame);
                                            if(vRet==0)
                                            {
                                                vRet = av_interleaved_write_frame( pRecordingAudioFC, &Pkt );
                                                if(vRet!=0)
                                                {
                                                    NSLog(@"write frame error %d", vRet);
                                                }
                                            }
                                            else
                                            {
                                                char pErrBuf[1024];
                                                int  vErrBufLen = sizeof(pErrBuf);
                                                av_strerror(vRet, pErrBuf, vErrBufLen);

                                                NSLog(@"vRet=%d, Err=%s",vRet,pErrBuf);
                                                NSLog(@"data_size=%d,framesize=%d",data_size, pOutputCodecContext->frame_size);
                                                NSLog(@"linesize=%d channels=%d", pAVFrame1->linesize[0], pAudioCodecCtx->channels);
                                                NSLog(@"nb_samples=%d, sample_rate=%d",pAVFrame1->nb_samples,pAVFrame1->sample_rate);
                                                
                                            }
#endif
                                        }
                                    }
                                    else
                                    {
                                        if(pAudioOutputFile!=NULL)
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
                
                if (pAVFrame1)    avcodec_free_frame(&pAVFrame1);
            }
        }
                
#else

      if (buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= AudioPacket.size)
      {
        int vRedudantHeaderOfAAC=0;
        tAACADTSHeaderInfo vxADTSHeader={0};
        uint8_t *pHeader = &(AudioPacket.data[0]);
          
         // If User didn't assign AAC encapsulate format, we should guess ourself.
         if(vAACType==eAAC_UNDEFINED)
         {   
            // 20130603
            // Parse audio data to see if there is ADTS header
            bIsADTSAAS = [AudioUtilities parseAACADTSHeader:pHeader ToHeader:(tAACADTSHeaderInfo *) &vxADTSHeader];
                           
            // If header has the syncword of adts_fixed_header
            // syncword = 0xFFF
            if(bIsADTSAAS)
            {
               vAACType=eAAC_ADTS;
            }
            else
            {
               vAACType=eAAC_RAW;
            }
         }
         
         // remove ADTS or LATM header of AAC data
         if(vAACType==eAAC_ADTS)
         {
            vRedudantHeaderOfAAC = 7;
         }
         
          if(vRecordingStatus==eRecordRecording)
          {
              int vRet=0;
              AVPacket Pkt={0};
              av_init_packet(&Pkt);
              
              Pkt.size = AudioPacket.size-vRedudantHeaderOfAAC;
              Pkt.data = AudioPacket.data+vRedudantHeaderOfAAC;
              
              // TODO: This stream_index may be retrieved from pRecordingAudioFC
              Pkt.stream_index = 1;//AudioPacket.stream_index;
              //Pkt.flags |= AV_PKT_FLAG_KEY;
              
#if 0 // Debug when recording has error
              {
                  AVStream *pst = NULL;
                  AVCodecContext *pCodecCtx = NULL;
                  pst= pRecordingAudioFC->streams[1];
                  pCodecCtx = pst->codec;
                  
                  // sampling_frequency_index 0: 96000
                  bIsADTSAAS = [AudioUtilities parseAACADTSHeader:pHeader ToHeader:(tAACADTSHeaderInfo *) &vxADTSHeader];
                  NSLog(@"size=%d bitrate:%d samplerate:%d(%d) profile:%d",Pkt.size, pCodecCtx->bit_rate, \
                        pCodecCtx->sample_rate, vxADTSHeader.sampling_frequency_index, vxADTSHeader.profile);
                  //pCodecCtx->sample_aspect_ratio.num,pCodecCtx->sample_aspect_ratio.den);
              }
#endif
              
              if(pRecordingAudioFC)
              {
                  vRet = av_interleaved_write_frame( pRecordingAudioFC, &Pkt );
                  if(vRet!=0)  NSLog(@" %s:%d av_interleaved_write_frame fail", __FILE__, __LINE__);
              }
              else
              {
                  NSLog(@" %s:%d pRecordingAudioFC is NULL!!", __FILE__, __LINE__);
              }
          }
          
         // Remove ADTS Header
         memcpy((uint8_t *)buffer->mAudioData + buffer->mAudioDataByteSize, pHeader + vRedudantHeaderOfAAC, AudioPacket.size - vRedudantHeaderOfAAC);
         buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
         buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = AudioPacket.size - vRedudantHeaderOfAAC;
         buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket = aCodecCtx->frame_size;
         buffer->mAudioDataByteSize += (AudioPacket.size-vRedudantHeaderOfAAC);
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
                //NSLog(@"Error enqueuing audio buffer: %d", err);
            }
    }
    return 0;
}



-(id)initAudio: (AudioPacketQueue *) pInQueue withCodecCtx :(AVCodecContext *) pAudioCodecCtx{
    int i=0, audio_index = 1;
    int vBufferSize=0;    
    int err;
    
#if 1
    // support audio play when screen is locked
    NSError *setCategoryErr = nil;
    NSError *activationErr  = nil;
    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayback error:&setCategoryErr];
    [[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
#endif
    
    vAACType = eAAC_UNDEFINED;
    
    //pSampleQueue = [[NSMutableArray alloc] init];
    if(pInQueue)
    {
        audioPacketQueue = pInQueue;
    }
    else
    {
        audioPacketQueue = [[AudioPacketQueue alloc]initQueue];
    }
    
    if(pAudioCodecCtx==nil)
    {
        // use a fake definition to try to decode data, only work for some ipcam
        AVCodec         *pAudioCodec;

        pAudioCodec = avcodec_find_decoder(CODEC_ID_AAC);
        pAudioCodecCtx = avcodec_alloc_context3(pAudioCodec);
        if (!pAudioCodecCtx)
        {
            av_log(NULL, AV_LOG_ERROR, "Unsupported codec!\n");
        }
        
#if DECODE_AUDIO_BY_FFMPEG==0
        // Open codec
        if(avcodec_open2(pAudioCodecCtx, pAudioCodec, NULL) < 0)
        {
            av_log(NULL, AV_LOG_ERROR, "Cannot open audio decoder\n");
            
        }
#endif
        // If we use ffmpeg, we can know all codec info before receive data.
        // If we use live555, we need to assign codec info before receive data. but how?
        // we may get codec info from SDP or out-of-band method.
        // or we can get codec info after ffmpeg decode audio.
//        if (0)
//        {
//            pAudioCodecCtx->sample_rate = 12000;
//            pAudioCodecCtx->channels = 1;
//            pAudioCodecCtx->channel_layout = 4;
//            pAudioCodecCtx->bit_rate = 8000; // may useless
//            pAudioCodecCtx->frame_size = 1024; // how to caculate this by live555 info
//        }
        
        
#if DECODE_AUDIO_BY_FFMPEG==1
        // If we want to decode audio by ffmpeg, we should open codec here.
        if(avcodec_open2(aCodecCtx, pAudioCodec, NULL) < 0)
        {
            av_log(NULL, AV_LOG_ERROR, "Cannot open audio decoder\n");
            
        }
#endif

    }
    aCodecCtx = pAudioCodecCtx;
    
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
                if(pAudioCodecCtx->profile==FF_PROFILE_AAC_LOW)
                    audioFormat.mFormatFlags = kMPEG4Object_AAC_LC;
                else
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

            //NSLog(@"sample_rate=%d, channels=%d, channel_layout=%lld",pAudioCodecCtx->sample_rate, pAudioCodecCtx->channels, pAudioCodecCtx->channel_layout);
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
                
#if 0 // Test for reduce noise generated by ipcam
                audioFormat.mFramesPerPacket = 1024;
                audioFormat.mChannelsPerFrame = 1;
                //audioFormat.mFormatFlags = kAudioFormatFlagsAudioUnitCanonical;
                //audioFormat.mFormatFlags = kMPEG4Object_AAC_LC|kAudioFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsNonInterleaved;

                //audioFormat.mFormatID = kAudioFormatMPEG4AAC;
                //audioFormat.mFormatFlags = kMPEG4Object_AAC_LC;

//                audioFormat.mBitsPerChannel = 8;
//                audioFormat.mBytesPerFrame = 128;//audioFormat.mBitsPerChannel/8 * pAudioCodecCtx->channels;
//                audioFormat.mBytesPerPacket = 128;//audioFormat.mBitsPerChannel/8 * pAudioCodecCtx->channels * audioFormat.mFramesPerPacket;
//                audioFormat.mReserved = 0;
                
                [AudioUtilities PrintFileStreamBasicDescription:&audioFormat];
                
#endif
                
//                audioFormat.mFormatID = kAudioFormatLinearPCM;
//                audioFormat.mFormatFlags = kAudioFormatFlagIsBigEndian|kAudioFormatFlagIsAlignedHigh;
//                audioFormat.mSampleRate = pAudioCodecCtx->sample_rate; // 12000
//                audioFormat.mBitsPerChannel = pAudioCodecCtx->bits_per_coded_sample;//16;//16;
//                audioFormat.mChannelsPerFrame = pAudioCodecCtx->channels; // 2
//                audioFormat.mBytesPerFrame = 2*pAudioCodecCtx->channels;//4;
//                audioFormat.mBytesPerPacket = 2*pAudioCodecCtx->channels;//4;
//                audioFormat.mFramesPerPacket = 1;
//                audioFormat.mReserved = 0;
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
            else if((audioFormat.mFormatID == kAudioFormatLinearPCM)||
                    (audioFormat.mFormatID == kAudioFormatALaw)||
                     (audioFormat.mFormatID == kAudioFormatULaw))            
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
                
                //NSLog(@"bit_rate=%d, frame_size=%d",pAudioCodecCtx->bit_rate,pAudioCodecCtx->frame_size);
                if(pAudioCodecCtx->bit_rate==0) {
                    pAudioCodecCtx->bit_rate=0x100000;//0x50000;
                }
#if 1
                if(pAudioCodecCtx->frame_size==0) {
                    pAudioCodecCtx->frame_size=1024;
                    NSLog(@"pAudioCodecCtx->frame_size=0");
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
    
    AudioQueueAddPropertyListener(mQueue,
                                  kAudioQueueProperty_IsRunning,
                                  CheckAudioQueueRunningStatus,
                                  (__bridge void *)(self));
    return self;
}    


-(id)initAudio: (AudioPacketQueue *) pInQueue withCodecId :(int) vCodecId
withSampleRate: (int)vSampleRate
  withChannels:(int)vChannels
withFrameLength:(int)vFrameLength{

    AVCodecContext  *pAudioCodecCtx;
    AVCodec         *pAudioCodec;
   
    pAudioCodec = avcodec_find_decoder(vCodecId);//(CODEC_ID_AAC);
    pAudioCodecCtx = avcodec_alloc_context3(pAudioCodec);
    
#if DECODE_AUDIO_BY_FFMPEG==0
    // Open codec
    if(avcodec_open2(pAudioCodecCtx, pAudioCodec, NULL) < 0)
    {
        av_log(NULL, AV_LOG_ERROR, "Cannot open audio decoder\n");
        
    }
#endif
    
    // TODO: try to get the real information from this audio streaming instead of fixed value
    if (vCodecId == CODEC_ID_AAC)
    {
        pAudioCodecCtx->sample_rate = vSampleRate; //12000, 7687
        pAudioCodecCtx->channels = vChannels;
        pAudioCodecCtx->channel_layout = 4;
        pAudioCodecCtx->bit_rate = 8000; // may useless
        pAudioCodecCtx->frame_size = 1024;//vFrameLength//1024; // how to caculate this by live555 info
    }
    else if (vCodecId == CODEC_ID_PCM_ALAW)
    {
        pAudioCodecCtx->sample_rate = 8000;//[mysubsession getRtpTimestampFrequency];
        pAudioCodecCtx->channels = 1;
        pAudioCodecCtx->channel_layout = 4;
        pAudioCodecCtx->bit_rate = 12000; // may useless
        pAudioCodecCtx->frame_size = 1; // may useless
    }
    
#if DECODE_AUDIO_BY_FFMPEG==1
    // If we want to decode audio by ffmpeg, we should open codec here.
    if(avcodec_open2(pAudioCodecCtx, pAudioCodec, NULL) < 0)
    {
        av_log(NULL, AV_LOG_ERROR, "Cannot open audio decoder\n");
        
    }
#endif
    
    return [self initAudio: pInQueue withCodecCtx :pAudioCodecCtx];
}

- (void) SetVolume:(float)vVolume
{
    AudioQueueSetParameter(mQueue, kAudioQueueParam_Volume, vVolume);
}

- (int) Play{
    OSStatus eErr=noErr;
    
    int i;

    if(AudioStatus==eAudioRunning) return -1;
    
    AudioStatus = eAudioRunning;
    LastStartTime = 0;
    
    for(i=0;i<AUDIO_BUFFER_QUANTITY;i++)
    {
        eErr = [self putAVPacketsIntoAudioQueue:mBuffers[i]];
        if(eErr!=noErr)
        {
            NSLog(@"putAVPacketsIntoAudioQueue() error %ld", eErr);
            return -1;
        }
    }
    
    // 20130427 Test temparally    
    // Decodes enqueued buffers in preparation for playback

#if DECODE_AUDIO_BY_FFMPEG == 0
    eErr=AudioQueuePrime(mQueue, 0, NULL);
    if(eErr!=noErr)
    {
        NSLog(@"AudioQueuePrime() error %ld", eErr);
        return -1;
    }
#endif
    
    eErr=AudioQueueStart(mQueue, nil);
    if(eErr!=noErr)
    {
        NSLog(@"AudioQueueStart() error %ld", eErr);
        return -1;
    }
    
    return 0;
}

-(void)Stop:(BOOL)bStopImmediatelly{
    
    AudioStatus = eAudioStop;
    [vReConnectTimer invalidate];
    vReConnectTimer = nil;
    
    AudioQueueStop(mQueue, bStopImmediatelly);
    
    // Disposing of the audio queue also disposes of all its resources, including its buffers.
    AudioQueueDispose(mQueue, bStopImmediatelly);
    
    if (pSwrCtx)   swr_free(&pSwrCtx);
    NSLog(@"Dispose Apple Audio Queue");
}


-(int) getStatus{
    return AudioStatus;
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
- (void) RecordingSetAudioFormat:(int)vAudioFormat
{
    vRecordingAudioFormat = vAudioFormat;
}


// Use to write audio packet to the same destination
// The destination file should be already created and well set.
- (void) RecordingStartWithFC:(AVFormatContext *) pFC
{
    NSLog(@"RecordingStart");
    vRecordingStatus = eRecordInit;
    
    // TODO: check if pFC is still well defind...
    pRecordingAudioFC = pFC;
    pOutputCodecContext = pFC->streams[1]->codec;
    
    // The output format should be well set before invoke this function
    NSLog(@"RecordingStartWithFC::");
    av_dump_format(pRecordingAudioFC, 0, "UsePreviousSetting", 1);
    
    vRecordingStatus = eRecordRecording;
}


- (void) RecordingStopWithFC:(AVFormatContext *) pFC
{
    NSLog(@"RecordingStop");
    vRecordingStatus = eRecordStop;
    
}

// Use audio player to record audio as a file
// The destination file will be created once this function is invoked
- (void) RecordingStart:(NSString *)pRecordingFile
{
    int vRet=0;
    
    NSLog(@"RecordingStart");
    vRecordingStatus = eRecordInit;

    if(vRecordingAudioFormat==kAudioFormatMPEG4AAC)
    {
        AVOutputFormat *pOutputFormat=NULL;
        AVStream *pOutputStream=NULL;
        //AVCodecContext *pOutputCodecContext=NULL;
        AVCodec *pCodec=NULL;
        const char *pFilePath = [pRecordingFile UTF8String];
        
        // Create container
        pOutputFormat = av_guess_format( 0, pFilePath, 0 );
        
        pRecordingAudioFC = avformat_alloc_context();
        pRecordingAudioFC->oformat = pOutputFormat;
        strcpy( pRecordingAudioFC->filename, pFilePath );
        
        // Assign codec as the same codec of input data
        pCodec = avcodec_find_encoder(AV_CODEC_ID_AAC); // AV_CODEC_ID_AAC
        
        
#if 1
        // Add audio stream
        pOutputStream = avformat_new_stream( pRecordingAudioFC, pCodec );
        vRecordingAudioStreamIdx = pOutputStream->index;
        NSLog(@"Audio Stream:%d", (unsigned int)vRecordingAudioStreamIdx);
        pOutputCodecContext = pOutputStream->codec;
        avcodec_get_context_defaults3( pOutputCodecContext, pCodec );
#else
        // Add audio stream
        pOutputStream = avformat_new_stream( pRecordingAudioFC, 0 );
        vRecordingAudioStreamIdx = pOutputStream->index;
        NSLog(@"Audio Stream:%d", (unsigned int)vRecordingAudioStreamIdx);
        pOutputCodecContext = pOutputStream->codec;
        avcodec_get_context_defaults3( pOutputCodecContext, NULL );
#endif

        //pOutputCodecContext = pRecordingAudioFC->streams[vRecordingAudioStreamIdx]->codec;
#if 0
        // reference http://ffmpeg.org/doxygen/0.6/output-example_8c-source.html
        pOutputCodecContext->codec_type = AVMEDIA_TYPE_AUDIO;
        pOutputCodecContext->codec_id = AV_CODEC_ID_AAC;
        
        pOutputCodecContext->bit_rate = aCodecCtx->bit_rate;
        pOutputCodecContext->channels = aCodecCtx->channels;
        pOutputCodecContext->sample_rate = aCodecCtx->sample_rate;

#else
        // check why codec_id didn't set correct automatically
        pOutputCodecContext->codec_type = AVMEDIA_TYPE_AUDIO;
        pOutputCodecContext->codec_id = AV_CODEC_ID_AAC;
        pOutputCodecContext->bit_rate = aCodecCtx->bit_rate;
        NSLog(@"pOutputCodecContext bit_rate=%d", pOutputCodecContext->bit_rate);
        
        // Copy the codec attributes
        pOutputCodecContext->channels = aCodecCtx->channels;
        pOutputCodecContext->channel_layout = aCodecCtx->channel_layout;
        pOutputCodecContext->sample_rate = aCodecCtx->sample_rate;
        
        // AV_SAMPLE_FMT_U8P, AV_SAMPLE_FMT_S16P, AV_SAMPLE_FMT_FLTP
        // For WMA, AV_SAMPLE_FMT_FLTP
        pOutputCodecContext->sample_fmt = AV_SAMPLE_FMT_FLTP;//aCodecCtx->sample_fmt;
        pOutputCodecContext->sample_aspect_ratio = aCodecCtx->sample_aspect_ratio;
        
#endif
        NSLog(@"framesize=%d", pOutputCodecContext->frame_size);
        NSLog(@"channels=%d", pOutputCodecContext->channels);
        NSLog(@"sample_rate=%d",pOutputCodecContext->sample_rate);
        
        pOutputCodecContext->time_base.num = aCodecCtx->time_base.num;
        pOutputCodecContext->time_base.den = aCodecCtx->time_base.den;
        pOutputCodecContext->ticks_per_frame = aCodecCtx->ticks_per_frame;

        // Reference http://libav-users.943685.n4.nabble.com/Libav-user-AAC-encoding-error-td4657210.html
        // Native AAC encoder is experimental and so you need to set additional flag to use.flag to use.
        AVDictionary *opts = NULL;
        av_dict_set(&opts, "strict", "experimental", 0);
        
        if (avcodec_open2(pOutputCodecContext, pCodec, &opts) < 0) {
            fprintf(stderr, "\ncould not open codec\n");
        }
        
        av_dict_free(&opts);
        
        av_dump_format(pRecordingAudioFC, 0, pFilePath, 1);
        NSLog(@"==!!");
        
#if 0
        // For Audio, this part is no need
        if(aCodecCtx->extradata_size!=0)
        {
            NSLog(@"extradata_size !=0");
            // For WMA test only
            pOutputCodecContext->extradata_size = 0;
#if 0
            pOutputCodecContext->extradata = malloc(sizeof(uint8_t)*aCodecCtx->extradata_size);
            memcpy(pOutputCodecContext->extradata, aCodecCtx->extradata, aCodecCtx->extradata_size);
            pOutputCodecContext->extradata_size = aCodecCtx->extradata_size;
#endif
        }
        else
        {
            NSLog(@"extradata_size ==0");
        }
#endif
        
        if(pRecordingAudioFC->oformat->flags & AVFMT_GLOBALHEADER)
        {
            pOutputCodecContext->flags |= CODEC_FLAG_GLOBAL_HEADER;
        }
        
        if ( !( pRecordingAudioFC->oformat->flags & AVFMT_NOFILE ) )
        {
            avio_open( &pRecordingAudioFC->pb, pRecordingAudioFC->filename, AVIO_FLAG_WRITE );
        }
        
        
        vRet = avformat_write_header( pRecordingAudioFC, NULL );
        if(vRet==0)
        {
            NSLog(@"Audio File header write Success!!");
        }
        else
        {
            NSLog(@"Audio File header write Fail!!");
            return;
        }
    }
    else
    {
        pAudioOutputFile=fopen([pRecordingFile UTF8String],"wb");
        if (pAudioOutputFile==NULL)
        {
            NSLog(@"Open file %@ error",pRecordingFile);
            return;
        }
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
        if ( !pRecordingAudioFC )
            return;
        
        av_write_trailer( pRecordingAudioFC );
        
        if ( pRecordingAudioFC->oformat && !( pRecordingAudioFC->oformat->flags & AVFMT_NOFILE ) && pRecordingAudioFC->pb )
            avio_close( pRecordingAudioFC->pb );
        
        av_free( pRecordingAudioFC );
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
