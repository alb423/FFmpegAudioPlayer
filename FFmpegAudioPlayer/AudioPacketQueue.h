//
//  AudioPacketQueue.h
//  iFrameExtractor
//
//  Created by Liao KuoHsun on 13/4/19.
//
//

#import <Foundation/Foundation.h>
#include "libavformat/avformat.h"

@interface AudioPacketQueue : NSObject{
    NSMutableArray *pQueue;
    NSLock *pLock;

}
@property  (nonatomic)  NSInteger count;
@property  (nonatomic)  NSInteger size;
- (id) initQueue;
- (void) destroyQueue;
-(int) putAVPacket: (AVPacket *) pkt;
-(int) getAVPacket :(AVPacket *) pkt;
-(void)freeAVPacket:(AVPacket *) pkt;
@end
