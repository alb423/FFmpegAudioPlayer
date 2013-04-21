//
//  PlayAudio.m
//  iFrameExtractor
//
//  Created by Liao KuoHsun on 13/4/19.
//
//

#import "AudioPlayer.h"
@implementation AudioPlayer

#define AUDIO_BUFFER_SECONDS 1
#define AUDIO_BUFFER_QUANTITY 3
#define DECODE_AUDIO_BY_FFMPEG 1

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
    int gotFrame = 0;
    
    AudioQueueBufferRef buffer=audioQueueBuffer;
    
    av_init_packet(&AudioPacket);    
    buffer->mAudioDataByteSize = 0;
    buffer->mPacketDescriptionCount = 0;

    if(mIsRunning==false)
    {
        return 0 ;
    }
    //NSLog(@"get 1 from apQueue: %d", [audioPacketQueue count]);
    // If no data, we put silence audio
    // If AudioQueue buffer is empty, AudioQueue will stop. 
    if([audioPacketQueue count]==0)
    {
        int err, vSilenceDataSize = 1024*4;
        
        NSLog(@"Put Silence -- Need adjust circular buffer");
        @synchronized(self){
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
    
//    while (([audioPacketQueue count]>0) && (buffer->mPacketDescriptionCount < buffer->mPacketDescriptionCapacity))
    if(buffer->mPacketDescriptionCount < buffer->mPacketDescriptionCapacity)
    {
        //NSLog(@"aqueue:%d", [audioPacketQueue count]);
        [audioPacketQueue getAVPacket: &AudioPacket];
        
#if DECODE_AUDIO_BY_FFMPEG == 1 // decode by FFmpeg
        {
            uint8_t *pktData=NULL;
            int pktSize;
            int len=0;
            AVCodecContext   *pAudioCodecCtx = aCodecCtx;
            AVFrame *pAVFrame1 = pAudioFrame;
            pktData=AudioPacket.data;
            pktSize=AudioPacket.size;
            
            if(pAVFrame1==NULL)
                NSLog(@"pAVFrame1==NULL"); // bug here??
                      
            while(pktSize>0) {
                avcodec_get_frame_defaults(pAVFrame1);
                @synchronized(self){
                    len = avcodec_decode_audio4(pAudioCodecCtx, pAVFrame1, &gotFrame, &AudioPacket);
                }
                if(len<0){
                    gotFrame = 0;
                    printf("Error while decoding\n");
                    break;
                }
                if(gotFrame>0) {
                    int outCount=0;                    
                    int data_size = av_samples_get_buffer_size(NULL, pAudioCodecCtx->channels,
                                                               pAVFrame1->nb_samples,pAudioCodecCtx->sample_fmt, 0);
                    
                    if (buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= data_size/2) {
                        @synchronized(self){
                            if(pAudioCodecCtx->sample_fmt==AV_SAMPLE_FMT_FLTP){
                                int in_samples = pAVFrame1->nb_samples;


                                //                                if (buffer->mPacketDescriptionCount == 0)
                                {
                                    bufferStartTime.mSampleTime = LastStartTime+in_samples;
                                    bufferStartTime.mFlags = kAudioTimeStampSampleTimeValid;
                                    LastStartTime = bufferStartTime.mSampleTime;
                                }
                                
                                uint8_t pTemp[8][data_size];
                                uint8_t *pOut = (uint8_t *)&pTemp;
                                outCount = swr_convert(pSwrCtx,
                                                       (uint8_t **)(&pOut),
                                                       in_samples,
                                                       (const uint8_t **)pAVFrame1->extended_data,
                                                       in_samples);
#if 0
                                // We can use av_samples_alloc() and av_freep() for sample buffer
                                // But use a static array may be efficience
                                uint8_t *pOut=NULL;
                                int out_linesize=0;
                                av_samples_alloc(&pOut,
                                                 &out_linesize,
                                                 pAudioFrame->channels,
                                                 in_samples,
                                                 AV_SAMPLE_FMT_S16,
                                                 0
                                                 );
                                
                                outCount = swr_convert(pSwrCtx,
                                                       (uint8_t **)&pOut,
                                                       in_samples,
                                                       (const uint8_t **)pAudioFrame->extended_data,
                                                       in_samples);
                                // TODO: need free pOut
#endif
                                if(outCount<0)
                                    NSLog(@"swr_convert fail");
                                                                
#if 1
                                    memcpy((uint8_t *)buffer->mAudioData + buffer->mAudioDataByteSize, pOut, data_size/2);
                                    buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
                                    buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = data_size/2;
                                    buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket
                                    = 1;
                                    buffer->mAudioDataByteSize += data_size/2;
#else
                                    memcpy((uint8_t *)buffer->mAudioData + buffer->mAudioDataByteSize, pOut, outCount*pAudioFrame->channels);
                                    buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
                                    buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = outCount*pAudioFrame->channels;
                                    buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket
                                    = 1;
                                    buffer->mAudioDataByteSize += outCount*pAudioFrame->channels;
#endif
                            }
                        };
                        
                        buffer->mPacketDescriptionCount++;
                    }
                    gotFrame = 0;
                }
                pktSize-=len;
                pktData+=len;
            }
        }
                
#else
        if (buffer->mAudioDataBytesCapacity - buffer->mAudioDataByteSize >= AudioPacket.size) {
//            if (buffer->mPacketDescriptionCount == 0)
//            {
//                bufferStartTime.mSampleTime = LastStartTime+pAudioFrame->nb_samples;
//                bufferStartTime.mFlags = kAudioTimeStampSampleTimeValid;
//                LastStartTime = bufferStartTime.mSampleTime;
//            }
            
            // omit 0x0010 (AAC ID)
            memcpy((uint8_t *)buffer->mAudioData + buffer->mAudioDataByteSize, AudioPacket.data, AudioPacket.size);
            
            buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
            buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = AudioPacket.size;
            buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket = aCodecCtx->frame_size;
            
            buffer->mAudioDataByteSize += AudioPacket.size;
            buffer->mPacketDescriptionCount++;
        }
#endif
        
        [audioPacketQueue freeAVPacket:&AudioPacket];
    }
    
    if (buffer->mPacketDescriptionCount > 0) {
        int err;
        
#if 0  // CBR
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
    
    audioPacketQueue = pInQueue;
    aCodecCtx = pAudioCodecCtx;
    pAudioFrame = avcodec_alloc_frame();
    
    if (audio_index >= 0) {
        AudioStreamBasicDescription audioFormat;
        audioFormat.mFormatID = -1;
        audioFormat.mSampleRate = pAudioCodecCtx->sample_rate;
        audioFormat.mFormatFlags = 0;
        switch (pAudioCodecCtx->codec_id) {
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
            default:
                NSLog(@"Error: audio format '%s' (%d) is not supported", pAudioCodecCtx->codec_name, pAudioCodecCtx->codec_id);
                audioFormat.mFormatID = kAudioFormatAC3;
                break;
        }
        
        if (audioFormat.mFormatID != -1) {
            
#if DECODE_AUDIO_BY_FFMPEG == 1            
            audioFormat.mFormatID = kAudioFormatLinearPCM;
            audioFormat.mFormatFlags = kAudioFormatFlagIsBigEndian|kAudioFormatFlagIsAlignedHigh;
            audioFormat.mSampleRate = pAudioCodecCtx->sample_rate; // 12000
            audioFormat.mBitsPerChannel = 16;//16;
            audioFormat.mChannelsPerFrame = pAudioCodecCtx->channels; // 2
            audioFormat.mBytesPerFrame = 2*pAudioCodecCtx->channels;//4;
            audioFormat.mBytesPerPacket = 2*pAudioCodecCtx->channels;//4;
            audioFormat.mFramesPerPacket = 1;
            audioFormat.mReserved = 0;
            
            pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                         pAudioCodecCtx->channel_layout,
                                         AV_SAMPLE_FMT_S16,
                                         pAudioCodecCtx->sample_rate,
                                         pAudioCodecCtx->channel_layout,
                                         AV_SAMPLE_FMT_FLTP,
                                         pAudioCodecCtx->sample_rate,
                                         0,
                                         0);
            if(swr_init(pSwrCtx)<0)
            {
                NSLog(@"swr_init()  fail");
                return nil;
            }
            
#else
            audioFormat.mBytesPerPacket = 0;
            audioFormat.mFramesPerPacket = pAudioCodecCtx->frame_size;
            audioFormat.mBytesPerFrame = 0;
            audioFormat.mChannelsPerFrame = pAudioCodecCtx->channels;
            audioFormat.mBitsPerChannel = 0;

            // For iron
            audioFormat.mFormatID = kAudioFormatLinearPCM;
            audioFormat.mFormatFlags = kAudioFormatFlagIsBigEndian|kAudioFormatFlagIsAlignedHigh;
            audioFormat.mSampleRate = pAudioCodecCtx->sample_rate; // 12000
            audioFormat.mBitsPerChannel = 16;//16;
            audioFormat.mChannelsPerFrame = pAudioCodecCtx->channels; // 2
            audioFormat.mBytesPerFrame = 2*pAudioCodecCtx->channels;//4;
            audioFormat.mBytesPerPacket = 2*pAudioCodecCtx->channels;//4;
            audioFormat.mFramesPerPacket = 1;
            audioFormat.mReserved = 0;
#endif
                        
            if ((err = AudioQueueNewOutput(&audioFormat, HandleOutputBuffer, (__bridge void *)(self), NULL, NULL, 0, &mQueue))!=noErr) {
                NSLog(@"Error creating audio output queue: %d", err);
            }
            else {
                
            // When I test, sometimes the data from network may loss information
            if(pAudioCodecCtx->bit_rate==0) {
                pAudioCodecCtx->bit_rate=0x50000;
            }
                
            vBufferSize = [self DeriveBufferSize:audioFormat withPacketSize:pAudioCodecCtx->bit_rate/8 withSeconds:AUDIO_BUFFER_SECONDS];
                
                for (i = 0; i < AUDIO_BUFFER_QUANTITY; i++) {
                    NSLog(@"%d packet capacity, %d byte capacity", (int)(pAudioCodecCtx->sample_rate * AUDIO_BUFFER_SECONDS / pAudioCodecCtx->frame_size + 1), (int)vBufferSize);
                    

                    if ((err = AudioQueueAllocateBufferWithPacketDescriptions(mQueue, vBufferSize, 1, &mBuffers[i]))!=noErr) {
                        NSLog(@"Error: Could not allocate audio queue buffer: %d", err);
                        AudioQueueDispose(mQueue, YES);
                        break;
                    }
              
                    
//                    if ((err = AudioQueueAllocateBufferWithPacketDescriptions(mQueue, pAudioCodecCtx->bit_rate * AUDIO_BUFFER_SECONDS / 8, pAudioCodecCtx->sample_rate * AUDIO_BUFFER_SECONDS / pAudioCodecCtx->frame_size + 1, &mBuffers[i]))!=noErr) {
//                        NSLog(@"Error: Could not allocate audio queue buffer: %d", err);
//                        AudioQueueDispose(mQueue, YES);
//                        break;
//                    }
                }
            }
        }
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
    // Decodes enqueued buffers in preparation for playback
    
//    eErr=AudioQueuePrime(mQueue, 0, NULL);
//    if(eErr!=noErr)
//    {
//        NSLog(@"AudioQueuePrime() error %ld", eErr);
//        return;
//    }
    
    //
    eErr=AudioQueueStart(mQueue, nil);
    if(eErr!=noErr)
    {
        NSLog(@"AudioQueueStart() error %ld", eErr);
    }
}

-(void)Stop:(BOOL)bStopImmediatelly{
    
    mIsRunning = false;
    // TODO: some bug about mQueue
    AudioQueueStop(mQueue, true);
    
    // Disposing of the audio queue also disposes of all its resources, including its buffers.
    AudioQueueDispose(mQueue, true);
    
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

#pragma mark - Test tool of Audio
- (void) PrintFileStreamBasicDescription:(NSString *) filePath{
    OSStatus status;
    UInt32 size;
    AudioFileID audioFile;
    AudioStreamBasicDescription dataFormat;
    
    CFURLRef URL = (__bridge CFURLRef)[NSURL fileURLWithPath:filePath];
    //    status=AudioFileOpenURL(URL, kAudioFileReadPermission, kAudioFileAAC_ADTSType, &audioFile);
    status=AudioFileOpenURL(URL, kAudioFileReadPermission, 0, &audioFile);
    if (status != noErr) {
        NSLog(@"*** Error *** PlayAudio - play:Path: could not open audio file. Path given was: %@", filePath);
        return ;
    }
    else {
        NSLog(@"*** OK *** : %@", filePath);
    }
    
    size = sizeof(dataFormat);
    AudioFileGetProperty(audioFile, kAudioFilePropertyDataFormat, &size, &dataFormat);
    if(size>0){
        NSLog(@"mFormatID=%d", (signed int)dataFormat.mFormatID);
        NSLog(@"mFormatFlags=%d", (signed int)dataFormat.mFormatFlags);
        NSLog(@"mSampleRate=%ld", (signed long int)dataFormat.mSampleRate);
        NSLog(@"mBitsPerChannel=%d", (signed int)dataFormat.mBitsPerChannel);
        NSLog(@"mBytesPerFrame=%d", (signed int)dataFormat.mBytesPerFrame);
        NSLog(@"mBytesPerPacket=%d", (signed int)dataFormat.mBytesPerPacket);
        NSLog(@"mChannelsPerFrame=%d", (signed int)dataFormat.mChannelsPerFrame);
        NSLog(@"mFramesPerPacket=%d", (signed int)dataFormat.mFramesPerPacket);
        NSLog(@"mReserved=%d", (signed int)dataFormat.mReserved);
    }
    
    AudioFileClose(audioFile);
}


static void writeWavHeader(AVCodecContext *pAudioCodecCtx,AVFormatContext *pFormatCtx,FILE *wavFile)
{
    char *data;
    int32_t long_temp;
    int16_t short_temp;
    int16_t BlockAlign;
    int32_t fileSize;
    int32_t audioDataSize;
    
    int vBitsPerSample = 0;
    switch(pAudioCodecCtx->sample_fmt) {
        case AV_SAMPLE_FMT_S16:
            vBitsPerSample=16;
            break;
        case AV_SAMPLE_FMT_S32:
            vBitsPerSample=32;
            break;
        case AV_SAMPLE_FMT_U8:
            vBitsPerSample=8;
            break;
        default:
            vBitsPerSample=16;
            break;
    }
    
    audioDataSize=(pFormatCtx->duration)*(vBitsPerSample/8)*(pAudioCodecCtx->sample_rate)*(pAudioCodecCtx->channels);
    fileSize=audioDataSize+36;
    
    // =============
    // fmt subchunk
    data="RIFF";
    fwrite(data,sizeof(char),4,wavFile);
    fwrite(&fileSize,sizeof(int32_t),1,wavFile);
    
    //"WAVE"
    data="WAVE";
    fwrite(data,sizeof(char),4,wavFile);
    
    
    // =============
    // fmt subchunk
    data="fmt ";
    fwrite(data,sizeof(char),4,wavFile);
    
    // SubChunk1Size (16 for PCM)
    long_temp=16;
    fwrite(&long_temp,sizeof(int32_t),1,wavFile);
    
    // AudioFormat, 1=PCM
    short_temp=0x01;
    fwrite(&short_temp,sizeof(int16_t),1,wavFile);
    
    // NumChannels (mono=1, stereo=2)
    short_temp=(pAudioCodecCtx->channels);
    fwrite(&short_temp,sizeof(int16_t),1,wavFile);
    
    // SampleRate (U32)
    long_temp=(pAudioCodecCtx->sample_rate);
    fwrite(&long_temp,sizeof(int32_t),1,wavFile);
    
    // ByteRate (U32)
    long_temp=(vBitsPerSample/8)*(pAudioCodecCtx->channels)*(pAudioCodecCtx->sample_rate);
    fwrite(&long_temp,sizeof(int32_t),1,wavFile);
    
    // BlockAlign (U16)
    BlockAlign=(vBitsPerSample/8)*(pAudioCodecCtx->channels);
    fwrite(&BlockAlign,sizeof(int16_t),1,wavFile);
    
    // BitsPerSaympe (U16)
    short_temp=(vBitsPerSample);
    fwrite(&short_temp,sizeof(int16_t),1,wavFile);
    
    // =============
    // Data Subchunk
    data="data";
    fwrite(data,sizeof(char),4,wavFile);
    
    // SubChunk2Size
    fwrite(&audioDataSize,sizeof(int32_t),1,wavFile);
    
    fseek(wavFile,44,SEEK_SET);
}


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
    
    writeWavHeader(pAudioCodecCtx,pFormatCtx,wavFile);
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
//        @synchronized(self){
//            av_free_packet(&AudioPacket);
//        };
    }
    fseek(wavFile,40,SEEK_SET);
    fwrite(&audioFileSize,1,sizeof(int32_t),wavFile);
    audioFileSize+=36;
    fseek(wavFile,4,SEEK_SET);
    fwrite(&audioFileSize,1,sizeof(int32_t),wavFile);
    fclose(wavFile);
    
}

-(id) initForDecodeAudioFile: (NSString *) FilePathIn ToPCMFile:(NSString *) FilePathOut {
    // Test to write a audio file into PCM format file
    FILE *wavFile=NULL;
    AVPacket AudioPacket={0};
    AVFrame  *pAVFrame1;
    int iFrame=0;
    uint8_t *pktData=NULL;
    int pktSize, audioFileSize=0;
    int gotFrame=0;
    
    AVCodec         *pAudioCodec;
    AVCodecContext  *pAudioCodecCtx;
    AVFormatContext *pAudioFormatCtx;

    int audioStream = -1;
    
    avcodec_register_all();
    av_register_all();
    avformat_network_init();

    pAudioFormatCtx = avformat_alloc_context();
    
    if(avformat_open_input(&pAudioFormatCtx, [FilePathIn cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0){
        av_log(NULL, AV_LOG_ERROR, "Couldn't open file\n");
    }

    if(avformat_find_stream_info(pAudioFormatCtx,NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't find stream information\n");
    }
    
    av_dump_format(pAudioFormatCtx, 0, [FilePathIn UTF8String], 0);

    int i;
    for(i=0;i<pAudioFormatCtx->nb_streams;i++){
        if(pAudioFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_AUDIO){
            audioStream=i;
            break;
        }
    }
    if(audioStream<0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find a audio stream in the input file\n");
        return nil;
    }
    

    pAudioCodecCtx = pAudioFormatCtx->streams[audioStream]->codec;
    pAudioCodec = avcodec_find_decoder(pAudioCodecCtx->codec_id);
    if(pAudioCodec == NULL) {
        av_log(NULL, AV_LOG_ERROR, "Unsupported audio codec!\n");
    }
    
    // If we want to change the argument about decode
    // We should set before invoke avcodec_open2()
    if(avcodec_open2(pAudioCodecCtx, pAudioCodec, NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot open audio decoder\n");
    }
    
    
    //pSwrCtx = swr_alloc();
    
    pSwrCtx = swr_alloc_set_opts(pSwrCtx,
                                 pAudioCodecCtx->channel_layout,
                                 AV_SAMPLE_FMT_S16,
                                 pAudioCodecCtx->sample_rate,
                                 pAudioCodecCtx->channel_layout,
                                 AV_SAMPLE_FMT_FLTP,
                                 pAudioCodecCtx->sample_rate,
                                 0,
                                 0);

    
    if(swr_init(pSwrCtx)<0)
    {
        NSLog(@"swr_init()  fail");
        return nil;
    }
    
    wavFile=fopen([FilePathOut UTF8String],"wb");
    if (wavFile==NULL)
    {
        printf("open file for writing error\n");
        return self;
    }

    pAVFrame1 = avcodec_alloc_frame();
    av_init_packet(&AudioPacket);
    
    int buffer_size = AVCODEC_MAX_AUDIO_FRAME_SIZE + FF_INPUT_BUFFER_PADDING_SIZE;
    uint8_t buffer[buffer_size];
    AudioPacket.data = buffer;
    AudioPacket.size = buffer_size;
    
    writeWavHeader(pAudioCodecCtx,pAudioFormatCtx,wavFile);
    while(av_read_frame(pAudioFormatCtx,&AudioPacket)>=0) {
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
                if(gotFrame) {
                    int data_size = av_samples_get_buffer_size(NULL, pAudioCodecCtx->channels,
                                                               pAVFrame1->nb_samples,pAudioCodecCtx->sample_fmt, 1);
                    
                    // Resampling 
                    if(pAudioCodecCtx->sample_fmt==AV_SAMPLE_FMT_FLTP){
                        int in_samples = pAVFrame1->nb_samples;
                        int outCount=0;
                        uint8_t *out=NULL;
                        int out_linesize;
                        av_samples_alloc(&out,
                                         &out_linesize,
                                         pAVFrame1->channels,
                                         in_samples,
                                         AV_SAMPLE_FMT_S16,
                                         0
                                         );
                        outCount = swr_convert(pSwrCtx,
                                               (uint8_t **)&out,
                                               in_samples,
                                               (const uint8_t **)pAVFrame1->extended_data,
                                               in_samples);
                                        
                        if(outCount<0)
                            NSLog(@"swr_convert fail");
                        
                        fwrite(out,  1, data_size/2, wavFile);
                        audioFileSize+=data_size/2;                        
                    }
                    
                    fflush(wavFile);
                    gotFrame = 0;
                }
                pktSize-=len;
                pktData+=len;
            }
        }
        [audioPacketQueue freeAVPacket:&AudioPacket];        
//        @synchronized(self){
//            av_free_packet(&AudioPacket);
//        };
    }
    fseek(wavFile,40,SEEK_SET);
    fwrite(&audioFileSize,1,sizeof(int32_t),wavFile);
    audioFileSize+=36;
    fseek(wavFile,4,SEEK_SET);
    fwrite(&audioFileSize,1,sizeof(int32_t),wavFile);
    fclose(wavFile);
    
    if (pSwrCtx)   swr_free(&pSwrCtx);
    if (pAVFrame1)    avcodec_free_frame(&pAVFrame1);
    if (pAudioCodecCtx) avcodec_close(pAudioCodecCtx);
    if (pAudioFormatCtx) {
        avformat_close_input(&pAudioFormatCtx);
    }
    return self;
}



@end
