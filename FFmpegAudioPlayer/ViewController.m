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
//#define AUDIO_TEST_PATH @"AAC_12khz_Mono_5.aac"
//#define AUDIO_TEST_PATH @"test_mono_8000Hz_8bit_PCM.wav"
//#define AUDIO_TEST_PATH @"output.pcm"
    
// WMA Sample plz reference http://download.wavetlan.com/SVV/Media/HTTP/WMA/WindowsMediaPlayer/
//#define AUDIO_TEST_PATH @"WMP_Test11-WMA_WMA2_Mono_64kbps_44100Hz-Eric_Clapton-Wonderful_Tonight.WMA"
//#define AUDIO_TEST_PATH @"WMP_Test12 - WMA_WMA2_Stereo_64kbps_44100Hz - Eric_Clapton-Wonderful_Tonight.WMA"

// === MMS URL ===
// plz reference http://alyzq.com/?p=777
// Stereo, 64kbps, 48000Hz
#define AUDIO_TEST_PATH @"mms://bcr.media.hinet.net/RA000009"
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


@interface ViewController (){
    UIAlertView *pLoadRtspAlertView;
    UIActivityIndicatorView *pIndicator;
    NSTimer *vLoadRtspAlertViewtimer;
    //NSTimer *vVisualizertimer;
    
    NSString *pUserSelectedURL;
    UIPickerView *PlayTimePickerView;
}
@end


@implementation ViewController
{
    NSInteger vTestCase;
    
    NSInteger vPlayTimerSecond, vPlayTimerMinute;
    NSArray *PlayTimerSecondOptions;
    NSArray *PlayTimerMinuteOptions;
}

@synthesize URLListData, URLNameToDisplay, VolumeBar;

// When unitest is selected, we should disable error prompt msgbox of UI
#define _UNITTEST_FOR_ALL_URL_ 0
#define _UNITTEST_PLAY_INTERVAL_ 30


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


- (void)ProcessJsonDataForBroadCastURL:(NSData *)pJsonData
{
    //parse out the json data
    NSError* error;
    
    NSMutableDictionary* jsonDictionary = [NSJSONSerialization JSONObjectWithData:pJsonData //1
                                                                          options:NSJSONReadingAllowFragments
                                                                            error:&error];
    if(error!=nil)
    {
        //NSString* aStr;
        //aStr = [[NSString alloc] initWithData:pJsonData encoding:NSUTF8StringEncoding];
        //NSLog(@"str=%@",aStr);
        
        NSLog(@"json transfer error %@", error);
        return;
        
    }
    
    // 1) retrieve the URL list into NSArray
    // A simple test of URLListData
    URLListData = [jsonDictionary objectForKey:@"url_list"];
    if(URLListData==nil)
    {
        NSLog(@"URLListData load error!!");
        return;
    }
    //NSLog(@"URLListData=%@",URLListData);
    
}

-(void)runNextTestCase:(NSTimer *)timer {
    
    if(timer!=nil)
    {
        [self StopPlayAudio:nil];
        
        if(vTestCase==[URLListData count])
        {
            [timer invalidate];
            return;
        }
        else
        {
            vTestCase++;
        
            NSDictionary *URLDict = [URLListData objectAtIndex:vTestCase];
            pUserSelectedURL = [URLDict valueForKey:@"url"];
            [self PlayAudio:_PlayAudioButton];
        }
    }
}


- (void)viewDidLoad
{    
    // init 
    NSString *pAudioPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:DEFAULT_BROADCAST_URL];
    NSData *pJsonData = [[NSFileManager defaultManager] contentsAtPath:pAudioPath];
    //NSData* pJsonData = [NSData dataWithContentsOfFile:pAudioPath];
    
    //NSLog(@"jsondata : %@", pJsonData);
    [self ProcessJsonDataForBroadCastURL:pJsonData];
    pAudioPath=nil;
    pJsonData = nil;
    
    // init Volumen Bar
    VolumeBar.maximumValue = 1.0;
    VolumeBar.minimumValue = 0.0;
    VolumeBar.value = 0.5;
    VolumeBar.continuous = YES;
    [aPlayer SetVolume:VolumeBar.value];
    
    
    // init PlayTimer options
    PlayTimerSecondOptions = [[NSArray alloc]initWithObjects:@"0",@"5",@"10",@"15",@"20",@"25",@"30",@"35",@"40",@"45",@"50",@"55",@"60",nil];
    PlayTimerMinuteOptions = [[NSArray alloc]initWithObjects:@"0",@"1",@"2",@"3",@"4",@"5",@"6",@"7",@"8",@"9",@"10",@"11",@"12",nil];

    
#if _UNITTEST_FOR_ALL_URL_ == 1 // Unittest
    vTestCase = 0;
    NSDictionary *URLDict = [URLListData objectAtIndex:vTestCase];
    pUserSelectedURL = [URLDict valueForKey:@"url"];
    [self PlayAudio:_PlayAudioButton];
    
    [NSTimer scheduledTimerWithTimeInterval:_UNITTEST_PLAY_INTERVAL_
                                       target:self
                                     selector:@selector(runNextTestCase:)
                                     userInfo:nil
                                      repeats:YES];
    
#endif
    
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
#if _UNITTEST_FOR_ALL_URL_ != 1
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
    
    if(vLoadRtspAlertViewtimer)
    {
        [vLoadRtspAlertViewtimer invalidate];
        vLoadRtspAlertViewtimer = nil;
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
    vLoadRtspAlertViewtimer = [NSTimer scheduledTimerWithTimeInterval:30
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
    
    //[vVisualizertimer invalidate];
    //vVisualizertimer = nil;
    //[visualizer clear];
    //visualizer = nil;
    //[visualizer deinit];
}







- (IBAction)PlayAudio:(id)sender {
    
    UIButton *vBn = (UIButton *)sender;

#if 0
    [AudioUtilities initForDecodeAudioFile:AUDIO_TEST_PATH ToPCMFile:@"/Users/liaokuohsun/1.wav"];
    NSLog(@"Save file to /Users/liaokuohsun/1.wav");
    return;
#endif
    
    CGRect vxRect;
    vxRect.origin.x = 10;
    vxRect.origin.y = 10;
    vxRect.size.height = 300;
    vxRect.size.width = 300;
    
    //visualizer = [[Visualizer alloc] initWithFrame:vxRect];
    //[self.view addSubview:visualizer];
    
    if([vBn.currentTitle isEqualToString:@"Stop"])
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
#if _UNITTEST_FOR_ALL_URL_ != 1
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
            sleep(5);
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self stopAlertView:nil];
            });
            
            if([aPlayer getStatus]!=eAudioRunning)
            {
                [aPlayer Play];
            }
            
#else
            //[visualizer setSampleRate:pAudioCodecCtx->sample_rate];
            // Dismiss alertview in main thread
            // Run Audio Player in main thread
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self stopAlertView:nil];
                sleep(5);
                if([aPlayer getStatus]!=eAudioRunning)
                {
                    [aPlayer Play];
                }
                
//                vVisualizertimer = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self
//                                                       selector:@selector(timerFired:) userInfo:nil repeats:YES];
                
                
            });
            
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
        IsLocalFile = FALSE;
    }
    else if( strncmp([pAudioInPath UTF8String], "mms:", 4)==0)
    {
        //replay "mms:" to "mmsh:" or "mmst:"
        pAudioInPath = [pAudioInPath stringByReplacingOccurrencesOfString:@"mms:" withString:@"mmsh:"];
//pAudioInPath = [pAudioInPath stringByReplacingOccurrencesOfString:@"mms:" withString:@"mmst:"];
        //NSLog(@"pAudioPath=%@", pAudioInPath);
        IsLocalFile = FALSE;
    }
    else if( strncmp([pAudioInPath UTF8String], "mmsh", 4)==0)
    {
        IsLocalFile = FALSE;
    }
    else
    {
        pAudioInPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:AUDIO_TEST_PATH];
        IsLocalFile = TRUE;
    }
        
    avcodec_register_all();
    av_register_all();
    if(IsLocalFile!=TRUE)
    {
        avformat_network_init();
    }
    
    @synchronized(self)
    {
        pFormatCtx = avformat_alloc_context();
    }
    
#if 1 // TCP
    AVDictionary *opts = 0;
    av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    NSLog(@"%@", pAudioInPath);
    
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
            NSLog(@"av_read_frame");
            if(vErr>=0)
            {
                if(vxPacket.stream_index==audioStream) {
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
    
//    if (pAudioCodecCtx) {
//        avcodec_close(pAudioCodecCtx);
//        pAudioCodecCtx = NULL;
//    }
//    if (pFormatCtx) {
//        avformat_close_input(&pFormatCtx);
//    }
    NSLog(@"Leave ReadFrame");
}


#pragma mark - URL_list TableView

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    NSLog(@"[URLListData count]=%d",[URLListData count]);
    return [URLListData count];
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    static NSString *tableIdentifier = @"Simple table";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:tableIdentifier];
    if(cell == nil){
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:tableIdentifier];
    }
    
    NSDictionary *URLDict = [URLListData objectAtIndex:indexPath.row];
    //NSLog(@"%@",[URLDict valueForKey:@"title"]);
    cell.textLabel.text = [URLDict valueForKey:@"title"];
    URLDict = nil;
    return cell;
}

-(void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{
    NSDictionary *URLDict = [URLListData objectAtIndex:indexPath.row];
    cell.textLabel.text = [URLDict valueForKey:@"title"];
    URLDict = nil;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Set the URL_TO_PLAY to the url user select
    NSDictionary *URLDict = [URLListData objectAtIndex:indexPath.row];
    pUserSelectedURL = [URLDict valueForKey:@"url"];
    URLNameToDisplay.text = [URLDict valueForKey:@"title"];
    URLNameToDisplay.textAlignment = NSTextAlignmentCenter;
}

#pragma mark - volume_bar Slider
- (IBAction)VolumeBarPressed:(id)sender {
    [aPlayer SetVolume:VolumeBar.value];
}


#pragma mark - Play Timer PickView
// reference http://blog.csdn.net/zzfsuiye/article/details/6644566
// reference http://blog.sina.com.cn/s/blog_7119b1a40100vxwv.html
// 返回pickerview的组件数
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)thePickerView {
    return 2;
}

// 返回每个组件上的行数
- (NSInteger)pickerView:(UIPickerView *)thePickerView numberOfRowsInComponent:(NSInteger)component {
    if(component==0)
    {
        return [PlayTimerMinuteOptions count];
    }
    else
    {
        return [PlayTimerSecondOptions count];
    }

}

// 设置每行显示的内容
- (NSString *)pickerView:(UIPickerView *)thePickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    
    if(component==0)
    {
        return [PlayTimerMinuteOptions objectAtIndex:row];
    }
    else
    {
        return [PlayTimerSecondOptions objectAtIndex:row];
    }
}

//使pickerview从底部出现
-(void) showPickerView {
    [UIView beginAnimations: @"Animation" context:nil];//设置动画
    [UIView setAnimationDuration:0.3];
    PlayTimePickerView.frame = CGRectMake(0,240, 320, 460);
    [UIView commitAnimations];
}

//使pickerview隐藏到屏幕底部
-(void) hidePickerView {
    [UIView beginAnimations:@"Animation"context:nil];
    [UIView setAnimationDuration:0.3];
    PlayTimePickerView.frame =CGRectMake(0,460, 320, 460);
    [UIView commitAnimations];
}

#if 0
//自定义pickerview使内容显示在每行的中间，默认显示在每行的左边
- (UIView *)pickerView:(UIPickerView *)pickerView viewForRow:(NSInteger)row forComponent:(NSInteger)component reusingView:(UIView *)view {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0f,0.0f, [pickerView rowSizeForComponent:component].width, [pickerView rowSizeForComponent:component].height)];
    if (row ==0) {
        label.text =@"男";
    }else {
        label.text =@"女";
    }
    
    //[label setTextAlignment:UITextAlignmentCenter];
    [label setTextAlignment:NSTextAlignmentCenter];
    return label;
}
#endif

//当你选中pickerview的某行时会调用该函数。
- (void)pickerView:(UIPickerView *)thePickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    NSLog(@"You select component:%d row %d",component, row);
    if(component==0)
    {
        vPlayTimerMinute = [[PlayTimerMinuteOptions objectAtIndex:row] intValue];
    }
    else
    {
        vPlayTimerSecond = [[PlayTimerSecondOptions objectAtIndex:row] intValue];
    }
}

-(void)PlayTimerFired:(NSTimer *)timer {
    NSLog(@"PlayTimerFired");
    [self StopPlayAudio:nil];
    if(timer!=nil)
    {
        [timer invalidate];
    }
}


- (IBAction)PlayTimerButtonPressed:(id)sender {
    static int bPickerViewVisible = 0;
    
    if (PlayTimePickerView==nil) {
        PlayTimePickerView = [[UIPickerView alloc] initWithFrame:CGRectMake(0,460, 320, 460)];
        PlayTimePickerView.delegate = self;
        PlayTimePickerView.dataSource = self;
        PlayTimePickerView.showsSelectionIndicator = YES; //选中某行时会和其他行显示不同
        [self.view addSubview:PlayTimePickerView];
        //PlayTimePickerView= nil;
    }
    
    if(bPickerViewVisible==0)
    {
        bPickerViewVisible = 1;
        [self showPickerView];
    }
    else
    {
        // Choose Time and then set timer to stop play
        int vSeconds=0;
        vSeconds = vPlayTimerMinute*60 + vPlayTimerSecond;
        NSLog(@"Set Play Time to %d Seconds", vSeconds);
        [NSTimer scheduledTimerWithTimeInterval:vSeconds                                         target:self
                                       selector:@selector(PlayTimerFired:)
                                       userInfo:nil
                                        repeats:YES];
        bPickerViewVisible = 0;
        [self hidePickerView];

    }
}


#pragma mark - ad_banner_view
#if 0
- (BOOL)bannerViewActionShouldBegin:(ADBannerView *)banner willLeaveApplication:(BOOL)willLeave
{
    NSLog(@"Banner view is beginning an ad action");
    BOOL shouldExecuteAction = [self allowActionToRun]; // your application implements this method
    if (!willLeave && shouldExecuteAction)
    {
        // insert code here to suspend any services that might conflict with the advertisement
    }
    return shouldExecuteAction;
}
#endif


@end
