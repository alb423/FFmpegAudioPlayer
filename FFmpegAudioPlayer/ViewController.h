//
//  ViewController.h
//  FFmpegAudioPlayer
//
//  Created by Liao KuoHsun on 13/4/19.
//  Copyright (c) 2013年 Liao KuoHsun. All rights reserved.
//

#import <UIKit/UIKit.h>
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#import "AudioPacketQueue.h"
#import "AudioPlayer.h"
//#import "Visualizer.h"

#define DEFAULT_BROADCAST_URL @"hinet_radio_json.json"

@interface ViewController : UIViewController <UIPickerViewDelegate, UIPickerViewDataSource>
//@interface ViewController : UIViewController <UIPickerViewDelegate>
{
	AVFormatContext *pFormatCtx;    
    AVCodecContext *pAudioCodecCtx;
    AVPacket packet;
    
    double audioClock;
    int audioStream;

    AudioPlayer *aPlayer;
    BOOL IsStop;
    BOOL IsLocalFile;
    
    //Visualizer *visualizer;

}

@property (weak, nonatomic) IBOutlet UIButton *PlayAudioButton;
@property (weak, nonatomic) IBOutlet UITableView *URLListView;
@property (strong, nonatomic) NSArray *URLListData;
@property (weak, nonatomic) IBOutlet UILabel *URLNameToDisplay;
@property (weak, nonatomic) IBOutlet UISlider *VolumeBar;

- (IBAction)PlayTimerButtonPressed:(id)sender;
- (IBAction)VolumeBarPressed:(id)sender;
- (IBAction)PlayAudio:(id)sender;
- (void)ProcessJsonDataForBroadCastURL:(NSData *)pJsonData;
@end
