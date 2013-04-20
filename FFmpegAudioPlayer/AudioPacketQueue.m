//
//  AudioPacketQueue.m
//  a queue to store AVPacket from ffmpeg
//
//  Created by Liao KuoHsun on 13/4/19.
//
//

#import "AudioPacketQueue.h"

@implementation AudioPacketQueue

@synthesize count;


- (id) initQueue
{
    self = [self init];
    if(self != nil)
    {
        pQueue = [[NSMutableArray alloc] init];
        pLock = [[NSLock alloc]init];
        count = 0;
    }
    return self;
}

// Useless in ARC mode
- (void) destroyQueue {
    count = 0;
    [pQueue removeAllObjects];
    if(pQueue) pQueue = nil;
    if(pLock) pLock = nil;
}

-(int) putAVPacket: (AVPacket *) pPacket{

    // memory leakage is related to pPacket    
    [pLock lock];
    
    NSLog(@"putAVPacket %d", [pQueue count]);   
    [pQueue addObject: [NSMutableData dataWithBytes:pPacket length:sizeof(*pPacket)]];
    count++;
    [pLock unlock];
    return 1;
}

-(int ) getAVPacket :(AVPacket *) pPacket{
    NSMutableData *packetData = nil;
    
    // Do we have any items?
    [pLock  lock];
    if ([pQueue count]>0) {
        packetData = [pQueue objectAtIndex:0];
        if(packetData!= nil)
        {
            [packetData getBytes:pPacket];
            packetData = nil;
            [pQueue removeObjectAtIndex: 0];
            count--;
        }
        [pLock unlock];
        return 1;
    }
    else
    {
        [pLock unlock];
        return 0;
    }

    return 0;
}

-(void)freeAVPacket:(AVPacket *) pPacket{
    [pLock  lock];
    av_free_packet(pPacket);
    [pLock unlock];
}


@end
