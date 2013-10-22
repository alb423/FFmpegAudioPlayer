//
//  ViewController.m
//  FFmpegAudioPlayer
//
//  Created by Liao KuoHsun on 13/4/19.
//  Copyright (c) 2013年 Liao KuoHsun. All rights reserved.
//


#import "ViewController.h"
#import "AudioPlayer.h"
#import "AudioUtilities.h"

#define WAV_FILE_NAME @"1.wav"

// If we read too fast, the size of aqQueue will increased quickly.
// If we read too slow, .
//#define LOCAL_FILE_DELAY_MS 80

// For 19_Austria.mp3
#define LOCAL_FILE_DELAY_MS 25

// Reference for AAC test file
// http://download.wavetlan.com/SVV/Media/HTTP/http-aac.htm
// http://download.wavetlan.com/SVV/Media/RTSP/darwin-aac.htm


// === LOCAL File ===
//#define AUDIO_TEST_PATH @"19_Austria.mp3"
#define AUDIO_TEST_PATH @"AAC_12khz_Mono_5.aac"
//#define AUDIO_TEST_PATH @"test_mono_8000Hz_8bit_PCM.wav"
//#define AUDIO_TEST_PATH @"output.pcm"
    
// WMA Sample plz reference http://download.wavetlan.com/SVV/Media/HTTP/WMA/WindowsMediaPlayer/
//#define AUDIO_TEST_PATH @"WMP_Test11-WMA_WMA2_Mono_64kbps_44100Hz-Eric_Clapton-Wonderful_Tonight.WMA"
//#define AUDIO_TEST_PATH @"WMP_Test12 - WMA_WMA2_Stereo_64kbps_44100Hz - Eric_Clapton-Wonderful_Tonight.WMA"

// TO Test
// #define AUDIO_TEST_PATH @"http://open.spotify.com/track/3wepnWWqG3Kn8yt3tj1wDy"

// === MMS URL ===
// plz reference http://alyzq.com/?p=777
// Stereo, 64kbps, 48000Hz
//#define AUDIO_TEST_PATH @"mms://bcr.media.hinet.net/RA000009"
//#define AUDIO_TEST_PATH @"mms://alive.rbc.cn/fm876"
// A error URL
//#define AUDIO_TEST_PATH @"mms://211.89.225.141/cnr001"

// === Valid RTSP URL ===
//#define AUDIO_TEST_PATH @"rtsp://216.16.231.19/BlackBerry.3gp"
//#define AUDIO_TEST_PATH @"rtsp://216.16.231.19/BlackBerry.mp4"
//#define AUDIO_TEST_PATH @"rtsp://mm2.pcslab.com/mm/7h800.mp4"
//#define AUDIO_TEST_PATH @"rtsp://216.16.231.19/The_Simpsons_S19E05_Treehouse_of_Horror_XVIII.3GP"


// === For Error Control Testing ===
// Test remote file
// Online Radio (can't play well)
//#define AUDIO_TEST_PATH @"rtsp://rtsplive.881903.com/radio-Web/cr2.3gp"

// Online Radio (invalid rtsp)
//#define AUDIO_TEST_PATH @"rtsp://211.89.225.101/live1"

// ("wma" audio format is not supported)
// #define AUDIO_TEST_PATH @"rtsp://media.iwant-in.net/pop"


// When unitest is selected, we should disable error prompt msgbox of UI
#define _UNITTEST_FOR_ALL_URL_ 0
#define _UNITTEST_PLAY_INTERVAL_ 30

@interface ViewController (){
    UIAlertView *pLoadRtspAlertView;
    UIActivityIndicatorView *pIndicator;
    NSTimer *vLoadRtspAlertViewTimer;
    NSTimer *vVisualizertimer;
    
    NSString *pUserSelectedURL;
}
@end


@implementation ViewController
{
    NSInteger vPlayTimerSecond, vPlayTimerMinute;
    NSArray *PlayTimerSecondOptions;
    NSArray *PlayTimerMinuteOptions;

#if _UNITTEST_FOR_ALL_URL_==1
    NSInteger vTestCase;
    NSString *pTestLog;
#endif
}

// 20130903 albert.liao modified start
@synthesize bRecordStart;
// 20130903 albert.liao modified end

//- (void)timerFired:(NSTimer *)timer
//{
//    int value;
//
//    while ([aPlayer.pSampleQueue count]) {
//        NSMutableData *packetData = [aPlayer.pSampleQueue objectAtIndex:0];
//        [packetData getBytes:&value];
//        if(value!=0)
//        [visualizer setPower:value];
//        [aPlayer.pSampleQueue removeObjectAtIndex:0];
//    }
//    [visualizer setNeedsDisplay];   
//} 

- (void)viewDidLoad
{
    IsStop = TRUE;
    [super viewDidLoad];
    return;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    NSLog(@"didReceiveMemoryWarning");
}

-(void)stopAlertView:(NSTimer *)timer {
    
    // Time out
    if(timer!=nil)
    {
        [timer invalidate];
#if _UNITTEST_FOR_ALL_URL_ == 1
        pTestLog = [pTestLog stringByAppendingString:@" RTSP Fail\n"];
#else
        UIAlertView *pErrAlertView = [[UIAlertView alloc] initWithTitle:@"\n\nRTSP error"
                                                                message:nil delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
        [pErrAlertView show];
#endif
        [self.PlayAudioButton setTitle:@"Play" forState:UIControlStateNormal];
    }
    
    if(pLoadRtspAlertView!=nil)
    {
        [pIndicator stopAnimating];
        [pLoadRtspAlertView dismissWithClickedButtonIndex:0 animated:YES];
        pIndicator = nil;
        pLoadRtspAlertView = nil;
    }
    
    if(vLoadRtspAlertViewTimer)
    {
        [vLoadRtspAlertViewTimer invalidate];
        vLoadRtspAlertViewTimer = nil;
    }
    else
        return;
    


}

-(void)startAlertView {
    pLoadRtspAlertView = [[UIAlertView alloc] initWithTitle:@"\n\nConnecting\nPlease Wait..."
                                                    message:nil delegate:self cancelButtonTitle:nil otherButtonTitles: nil];
    [pLoadRtspAlertView show];
    pIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    
    // Adjust the indicator so it is up a few pixels from the bottom of the alert
    pIndicator.center = CGPointMake(pLoadRtspAlertView.bounds.size.width / 2, pLoadRtspAlertView.bounds.size.height - 50);
    [pIndicator startAnimating];
    [pLoadRtspAlertView addSubview:pIndicator];
    
    // start a timer for 60 seconds, if rtsp cannot connect correctly.
    // we should dismiss alert view and let user can try again or leave this program
    vLoadRtspAlertViewTimer = [NSTimer scheduledTimerWithTimeInterval:30
                                     target:self
                                   selector:@selector(stopAlertView:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)StopPlayAudio:(id)sender {
    
    // Stop Producer
    [self stopFFmpegAudioStream];
    
    // Stop Consumer
    [aPlayer Stop:TRUE];
    //aPlayer = nil;    
    
    [self destroyFFmpegAudioStream];
    
    [vVisualizertimer invalidate];
    vVisualizertimer = nil;
    [visualizer clear];
    visualizer = nil;
    //[visualizer deinit];
}

- (IBAction)PlayAudio:(id)sender {
    
    UIButton *vBn = (UIButton *)sender;
    if(vBn==nil)
       vBn = _PlayAudioButton;
#if 0
    NSString *pAudioInPath;
    pAudioInPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:AUDIO_TEST_PATH];
    [AudioUtilities initForDecodeAudioFile:pAudioInPath ToPCMFile:@"/Users/liaokuohsun/1.wav"];
    NSLog(@"Save file to /Users/liaokuohsun/1.wav");
    return;
#endif
    
    CGRect vxRect;
    vxRect.origin.x = 10;
    vxRect.origin.y = 10;
    vxRect.size.height = 300;
    vxRect.size.width = 300;
    
    visualizer = [[Visualizer alloc] initWithFrame:vxRect];
    [self.view addSubview:visualizer];
    
    if(IsStop==false)//[vBn.currentTitle isEqualToString:@"Stop"])
    {
        [vBn setTitle:@"Play" forState:UIControlStateNormal];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
            [self StopPlayAudio:nil];
        });
    }
    else
    {
        [vBn setTitle:@"Stop" forState:UIControlStateNormal];        
        [self startAlertView];        
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
            if([self initFFmpegAudioStream]==FALSE)
            {
                NSLog(@"initFFmpegAudio fail");
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                [vBn setTitle:@"Play" forState:UIControlStateNormal];
                [self stopAlertView:nil];
#if _UNITTEST_FOR_ALL_URL_ == 1
                pTestLog = [pTestLog stringByAppendingString:@" RTSP Fail\n"];
#else
                UIAlertView *pErrAlertView = [[UIAlertView alloc] initWithTitle:@"\n\nRTSP error"
                                                                message:nil delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
                [pErrAlertView show];
#endif
                });
                return;
            }
            

            aPlayer = [[AudioPlayer alloc]initAudio:nil withCodecCtx:(AVCodecContext *) pAudioCodecCtx];

#if 0
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
                [self readFFmpegAudioFrameAndDecode];
            });
            
            // TODO: Currently We set sleep 5 seconds for buffer data
            // We should caculate the audio timestamp to make sure the buffer duration.
            if(IsLocalFile!=true)
            {
                sleep(AUDIO_BUFFER_TIME);
            }
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self stopAlertView:nil];
            });
            
            if([aPlayer getStatus]!=eAudioRunning)
            {
                int vRet = 0;
                vRet = [aPlayer Play];
                if(vRet<0)
                {
#if _UNITTEST_FOR_ALL_URL_ == 1
                    pTestLog = [pTestLog stringByAppendingString:@" decode Fail\n"];
#endif
                    NSLog(@"[aPlayer Play] error");

                }
                else
                {
                    ;//do nothing
                }
            }
            
#else
            //[visualizer setSampleRate:pAudioCodecCtx->sample_rate];
            // Dismiss alertview in main thread
            // Run Audio Player in main thread
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self stopAlertView:nil];
                if(IsLocalFile!=true)
                {
                    NSLog(@"sleep 5 seconds");
                    sleep(AUDIO_BUFFER_TIME);
                }
                
                if([aPlayer getStatus]!=eAudioRunning)
                {
                    int vRet = 0;
                    vRet = [aPlayer Play];
                    if(vRet<0)
                    {
#if _UNITTEST_FOR_ALL_URL_ == 1
                        pTestLog = [pTestLog stringByAppendingString:@" decode Fail\n"];
#endif
                        NSLog(@"[aPlayer Play] error");
                        
                    }
                }
                
//                vVisualizertimer = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self
//                                                       selector:@selector(timerFired:) userInfo:nil repeats:YES];
                
                
            });
            
            
            // Test only 20130908
//            bRecordStart = true;
//            [aPlayer RecordingSetAudioFormat:kAudioFormatMPEG4AAC];
//            [aPlayer RecordingStart:@"/Users/liaokuohsun/Audio3.mp4"];
            
            
            
            // Read ffmpeg audio packet in another thread
            [self readFFmpegAudioFrameAndDecode];
#endif
            
            [vBn setTitle:@"Play" forState:UIControlStateNormal];
        });
    }
}


#pragma mark - ffmpeg usage
-(BOOL) initFFmpegAudioStream{
    
    NSString *pAudioInPath;
    AVCodec  *pAudioCodec;
    AVDictionary *opts = 0;
    
    // 20130428 Test here
    {
        // Test sample :http://m.oschina.net/blog/89784
        uint8_t pInput[] = {0x0ff,0x0f9,0x058,0x80,0,0x1f,0xfc};
        tAACADTSHeaderInfo vxADTSHeader={0};        
        [AudioUtilities parseAACADTSHeader:pInput ToHeader:(tAACADTSHeaderInfo *) &vxADTSHeader];
    }
    
    // The pAudioInPath should be set when user select a url
    if(pUserSelectedURL==nil)
    {
        // use default url for testing
        pAudioInPath = AUDIO_TEST_PATH;
    }
    else
    {
        pAudioInPath = pUserSelectedURL;
    }
        
    if( strncmp([pAudioInPath UTF8String], "rtsp", 4)==0)
    {
        av_dict_set(&opts, "rtsp_transport", "tcp", 0); // can set "udp", "tcp", "http"
        IsLocalFile = FALSE;
    }
    else if( strncmp([pAudioInPath UTF8String], "mms:", 4)==0)
    {
        //replace "mms:" to "mmsh:" or "mmst:"
        av_dict_set(&opts, "rtsp_transport", "http", 0); // can set "udp", "tcp", "http"
        pAudioInPath = [pAudioInPath stringByReplacingOccurrencesOfString:@"mms:" withString:@"mmsh:"];
//pAudioInPath = [pAudioInPath stringByReplacingOccurrencesOfString:@"mms:" withString:@"mmst:"];
        //NSLog(@"pAudioPath=%@", pAudioInPath);
        IsLocalFile = FALSE;
    }
    else if( strncmp([pAudioInPath UTF8String], "mmsh", 4)==0)
    {
        av_dict_set(&opts, "rtsp_transport", "http", 0);
        IsLocalFile = FALSE;
    }
    else
    {
        av_dict_set(&opts, "rtsp_transport", "udp", 0);
        pAudioInPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:AUDIO_TEST_PATH];
        IsLocalFile = TRUE;
    }
        
    avcodec_register_all();
    av_register_all();
    av_log_set_level(AV_LOG_VERBOSE);
    if(IsLocalFile!=TRUE)
    {
        avformat_network_init();
    }
    
    @synchronized(self)
    {
        pFormatCtx = avformat_alloc_context();
    }
    
#if 1 // TCP
    //av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    NSLog(@"pAudioInPath=%@", pAudioInPath);
    
    // Open video file
    if(avformat_open_input(&pFormatCtx, [pAudioInPath cStringUsingEncoding:NSASCIIStringEncoding], NULL, &opts) != 0) {

        if( strncmp([pAudioInPath UTF8String], "mmst", 4)==0)
        {
            av_log(NULL, AV_LOG_ERROR, "Couldn't open mmst connection\n");
            pAudioInPath= [pAudioInPath stringByReplacingOccurrencesOfString:@"mmst:" withString:@"mmsh:"];
            if(avformat_open_input(&pFormatCtx, [pAudioInPath cStringUsingEncoding:NSASCIIStringEncoding], NULL, &opts) != 0)
            {
                av_log(NULL, AV_LOG_ERROR, "Couldn't open mmsh connection to %s\n", [pAudioInPath UTF8String]);
                return FALSE;
            }
        }
        else
        {
            av_log(NULL, AV_LOG_ERROR, "Couldn't open file\n");            
            return FALSE;
        }
    }


    
	av_dict_free(&opts);
#else // UDP
    if(avformat_open_input(&pFormatCtx, [pAudioInPath cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't open file\n");
        return FALSE;
    }
#endif
    
    pAudioInPath = nil;
    
    // Retrieve stream information
    if(avformat_find_stream_info(pFormatCtx,NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't find stream information\n");
        return FALSE;
    }
    
    // Dumpt stream information
    av_dump_format(pFormatCtx, 0, [pAudioInPath UTF8String], 0);
    
    
    // 20130329 albert.liao modified start
    // Find the first audio stream
    if ((audioStream =  av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, &pAudioCodec, 0)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find a audio stream in the input file\n");
        return FALSE;
    }
	
    if(audioStream>=0){
        
        NSLog(@"== Audio pCodec Information");
        NSLog(@"name = %s",pAudioCodec->name);
        NSLog(@"sample_fmts = %d",*(pAudioCodec->sample_fmts));
        if(pAudioCodec->profiles)
            NSLog(@"profiles = %s",pAudioCodec->name);
        else
            NSLog(@"profiles = NULL");
        
        // Get a pointer to the codec context for the video stream
        pAudioCodecCtx = pFormatCtx->streams[audioStream]->codec;
        
        // Find the decoder for the video stream
        pAudioCodec = avcodec_find_decoder(pAudioCodecCtx->codec_id);
        if(pAudioCodec == NULL) {
            av_log(NULL, AV_LOG_ERROR, "Unsupported audio codec!\n");
            return FALSE;
        }
        
        // Open codec
        if(avcodec_open2(pAudioCodecCtx, pAudioCodec, NULL) < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot open audio decoder\n");
            return FALSE;
        }
        
    }
    
    IsStop = FALSE;
    
    return TRUE;
}

-(void) stopFFmpegAudioStream{
    IsStop = TRUE;
    NSLog(@"stopFFmpegAudioStream");
}

-(void) destroyFFmpegAudioStream{
    IsStop = TRUE;
    NSLog(@"destroyFFmpegAudioStream");

    avformat_network_deinit();
    
// When IsStop == TRUE,
// the pFormatCtx and pAudioCodecCtx will be released in readFFmpegFrame automatically
//    @synchronized(self)
//    {
//        if (pAudioCodecCtx) {
//            avcodec_close(pAudioCodecCtx);
//            pAudioCodecCtx = NULL;
//        }
//        if (pFormatCtx) {
//            avformat_close_input(&pFormatCtx);
//            //av_close_input_file(pFormatCtx);
//        }
//    }
    
}


-(void) readFFmpegAudioFrameAndDecode {
    int vErr;
    AVPacket vxPacket;
    av_init_packet(&vxPacket);    
    
    if(IsLocalFile == TRUE)
    {
        while(IsStop==FALSE)
        {
            vErr = av_read_frame(pFormatCtx, &vxPacket);
            //NSLog(@"av_read_frame");
            if(vErr>=0)
            {
                if(vxPacket.stream_index==audioStream) {
                    
                    // 20130923 test
#if 0
                    AVPacket vxPacket2;
                    uint8_t *pTmp=NULL;
                    av_init_packet(&vxPacket2);
                    pTmp = malloc(vxPacket.size);
                    memcpy(pTmp, vxPacket.data, vxPacket.size);
                    //vxPacket.data = (uint8_t *)frameData;
                    vxPacket2.data = (uint8_t *)pTmp;
                    vxPacket2.size = vxPacket.size;
#endif
                    // 20130923 test end
                    
                    int ret = [aPlayer putAVPacket:&vxPacket];
                    if(ret <= 0)
                        NSLog(@"Put Audio Packet Error!!");
                    
                    // TODO: use pts/dts to decide the delay time
                    usleep(1000*LOCAL_FILE_DELAY_MS);
                }
                else
                {
                    //NSLog(@"receive unexpected packet!!");
                    av_free_packet(&vxPacket);
                }
            }
            else
            {
                NSLog(@"av_read_frame error :%s", av_err2str(vErr));
                IsStop = TRUE;
            }
        }
    }
    else
    {
        while(IsStop==FALSE)
        {
            vErr = av_read_frame(pFormatCtx, &vxPacket);
            
            if(vErr==AVERROR_EOF)
            {
                NSLog(@"av_read_frame error :%s", av_err2str(vErr));
                IsStop = TRUE;
            }
            else if(vErr==0)
            {
                if(vxPacket.stream_index==audioStream) {
                    int ret = [aPlayer putAVPacket:&vxPacket];
                    if(ret <= 0)
                        NSLog(@"Put Audio Packet Error!!");
                }
                else
                {
                    int i=0;
                    NSLog(@"receive unexpected packet, size=%d!!", vxPacket.size);
                    for(i=0;i<vxPacket.size;i+=7)
                    {
                        if(vxPacket.size-i>=8)
                        {
                        NSLog(@"%02X%02X%02X%02X %02X%02X%02X%02X",\
                              vxPacket.data[i],vxPacket.data[i+1],vxPacket.data[i+2],vxPacket.data[i+3],
                              vxPacket.data[i+4],vxPacket.data[i+5],vxPacket.data[i+6],vxPacket.data[i+7]);
                        }
                    // TODO: dump the packet
                    }
                    av_free_packet(&vxPacket);
                }
            }
            else
            {
                NSLog(@"av_read_frame error :%s", av_err2str(vErr));
                IsStop = TRUE;
            }
        }
    }

//    if (pAudioCodecCtx) {
//        avcodec_close(pAudioCodecCtx);
//        pAudioCodecCtx = NULL;
//    }
//    if (pFormatCtx) {
//        avformat_close_input(&pFormatCtx);
//    }
    NSLog(@"Leave ReadFrame");
}

#pragma mark - Recording Control 
- (IBAction)VideoRecordPressed:(id)sender {
    
    if(bRecordStart==true)
    {
        bRecordStart = false;
        [aPlayer RecordingStop];
    }
    else
    {
        // set recording format
        //vRecordingAudioFormat = kAudioFormatLinearPCM;// (Test ok)
        //vRecordingAudioFormat = kAudioFormatMPEG4AAC; //(need Test)
        bRecordStart = true;
#if 0
        [aPlayer RecordingSetAudioFormat:kAudioFormatLinearPCM];        
        [aPlayer RecordingStart:@"/Users/liaokuohsun/2.wav"];
#else
        [aPlayer RecordingSetAudioFormat:kAudioFormatMPEG4AAC];
        [aPlayer RecordingStart:@"/Users/liaokuohsun/Audio1.mp4"];
        //[aPlayer RecordingStart:@"/Users/liaokuohsun/Audio2.mp4"];
        //[aPlayer RecordingStart:@"/Users/liaokuohsun/AudioSaveDirectly.mp4"];
#endif
    }
    
    //[self startRecordingAlertView];
}


@end
