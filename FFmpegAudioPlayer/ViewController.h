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
#import "Visualizer.h"

#define AUDIO_BUFFER_TIME 10 // Seconds

@interface ViewController : UIViewController {
	AVFormatContext *pFormatCtx;    
    AVCodecContext *pAudioCodecCtx;
    AVPacket packet;
    
    double audioClock;
    int audioStream;

    AudioPlayer *aPlayer;
    BOOL IsStop;
    BOOL IsLocalFile;
    
    Visualizer *visualizer;

}

@property (weak, nonatomic) IBOutlet UIButton *PlayAudioButton;
- (IBAction)PlayAudio:(id)sender;

// 20130903 albert.liao modified start
@property BOOL bRecordStart;
- (IBAction)VideoRecordPressed:(id)sender;
// 20130903 albert.liao modified end

@end
