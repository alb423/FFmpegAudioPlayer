// Fig. 14.17: Visualizer.m
// VoiceRecorder
#import "Visualizer.h"

@implementation Visualizer

-(id) initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame])
    {
        powers = [[NSMutableArray alloc]
                  initWithCapacity:self.frame.size.width / 2];
    }
    
    sampleRate = 44100;
    
    return self; // return this BarVisualizer
    
}

- (void)setSampleRate:(float)p
{
    sampleRate = p;
}

// sets the current power in the recording
- (void)setPower:(float)p
{
   [powers addObject:[NSNumber numberWithFloat:p]]; // add value to powers
   
   // while there are enough entries to fill the entire screen
   while (powers.count * 2 > self.frame.size.width)
      [powers removeObjectAtIndex:0]; // remove the oldest entry
   
} // end method setPower:

// clears all the points from the visualizer
- (void)clear
{
   [powers removeAllObjects]; // remove all objects from powers
} // end method clear

// draws the visualizer
- (void)drawRect:(CGRect)rect
{
   // get the current graphics context
   CGContextRef context = UIGraphicsGetCurrentContext();
   CGSize size = self.frame.size;
   
//    NSLog(@"powers.count=%d", powers.count);
   // draw a line for each point in powers
   for (int i = 0; i < powers.count; i++)
   {
      // get next power level
      float newPower = [[powers objectAtIndex:i] floatValue];
       
       // move to a point above the middle of the screen
       CGContextMoveToPoint(context, i * 2, 0);
       CGContextAddLineToPoint(context, i * 2, size.height);
       CGContextSetRGBStrokeColor(context, 0, 0, 0, 1);
       CGContextStrokePath(context); // draw the line
       
      // calculate the height for this power level
      float height = (1 - newPower / sampleRate) * (size.height / 2);
      
      // move to a point above the middle of the screen
      CGContextMoveToPoint(context, i * 2, size.height / 2 - height);
      
      // add a line to a point below the middle of the screen
      CGContextAddLineToPoint(context, i * 2, size.height / 2 + height);
      
      // set the color for this line segment based on f
      CGContextSetRGBStrokeColor(context, 0, 1, 0, 1);
      CGContextStrokePath(context); // draw the line
   } // end for
} // end method drawRect:

// free Visualizer's memory
- (void) dealloc
{
    powers = nil;
} // end method dealloc
@end // end visualizer implementation


/**************************************************************************
 * (C) Copyright 2010 by Deitel & Associates, Inc. All Rights Reserved.   *
 *                                                                        *
 * DISCLAIMER: The authors and publisher of this book have used their     *
 * best efforts in preparing the book. These efforts include the          *
 * development, research, and testing of the theories and programs        *
 * to determine their effectiveness. The authors and publisher make       *
 * no warranty of any kind, expressed or implied, with regard to these    *
 * programs or to the documentation contained in these books. The authors *
 * and publisher shall not be liable in any event for incidental or       *
 * consequential damages in connection with, or arising out of, the       *
 * furnishing, performance, or use of these programs.                     *
 *                                                                        *
 * As a user of the book, Deitel & Associates, Inc. grants you the        *
 * nonexclusive right to copy, distribute, display the code, and create   *
 * derivative apps based on the code for noncommercial purposes only--so  *
 * long as you attribute the code to Deitel & Associates, Inc. and        *
 * reference www.deitel.com/books/iPhoneFP/. If you have any questions,   *
 * or specifically would like to use our code for commercial purposes,    *
 * contact deitel@deitel.com.                                             *
 *************************************************************************/

