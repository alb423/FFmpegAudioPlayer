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

@interface ViewController : UIViewController {
	AVFormatContext *pFormatCtx;    
    AVCodecContext *pAudioCodecCtx;
    AVPacket packet;
    
    double audioClock;
    int audioStream;
    AudioPacketQueue *apQueue;
    AudioPlayer *aPlayer;
    BOOL IsStop;
    BOOL IsLocalFile;
        
}

@property (weak, nonatomic) IBOutlet UIButton *PlayAudioButton;
- (IBAction)PlayAudio:(id)sender;

@end
