//
//  IosAudioController.h
//  Aruts
//
//  Created by Simon Epskamp on 10/11/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "TPCircularBuffer.h"

#ifndef max
#define max( a, b ) ( ((a) > (b)) ? (a) : (b) )
#endif

#ifndef min
#define min( a, b ) ( ((a) < (b)) ? (a) : (b) )
#endif


@interface IosAudioController : NSObject {
	AudioComponentInstance audioUnit;
	AudioBuffer tempBuffer; // this will hold the latest data from the microphone
    
@public
    TPCircularBuffer incomingCircularBuffer;
    int pkgtotal;
}

@property (readwrite) int pkgtotal;
@property (readonly) AudioComponentInstance audioUnit;
@property (readonly) AudioBuffer tempBuffer;

- (void) start;
- (void) stop;
- (void) processAudio: (AudioBufferList*) bufferList;
- (void) loadDataFromFile;

@end

// setup a global iosAudio variable, accessible everywhere
extern IosAudioController* iosAudio;