//
//  IosAudioController.m
//  Aruts
//
//  Created by Simon Epskamp on 10/11/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "IosAudioController.h"
#import <AudioToolbox/AudioToolbox.h>

#define kGraphSampleRate 44100.0
#define kOutputBus 0
#define kInputBus 1

IosAudioController* iosAudio;

void checkStatus(int status){
	if (status) {
		printf("Status not 0! %d\n", status);
//		exit(1);
	}
}



static OSStatus playbackCallback(void *inRefCon,
								 AudioUnitRenderActionFlags *ioActionFlags,
								 const AudioTimeStamp *inTimeStamp,
								 UInt32 inBusNumber,
								 UInt32 inNumberFrames,
								 AudioBufferList *ioData) {
    // Notes: ioData contains buffers (may be more than one!)
    // Fill them up as much as you can. Remember to set the size value in each buffer to match how
    // much data is in the buffer.
    NSLog(@"muffers %d", ioData->mNumberBuffers);
    UInt32 size = 2048;
    if (iosAudio->incomingCircularBuffer.fillCount>size){
        NSLog(@"Playing %d", iosAudio->incomingCircularBuffer.fillCount);
        iosAudio.pkgtotal -=2;
        int32_t availableBytes;
        SInt16 *databuffer = TPCircularBufferTail(&iosAudio->incomingCircularBuffer, &availableBytes);
        memcpy(ioData->mBuffers[0].mData, databuffer, size);
        ioData->mBuffers[0].mDataByteSize = size; // indicate how much data we wrote in the buffer
        TPCircularBufferConsume(&iosAudio->incomingCircularBuffer, size);
    }else{
    }
    
    return noErr;
}

/**
 This callback is called when the audioUnit needs new data to play through the
 speakers. If you don't have any, just don't write anything in the buffers
 *//*
static OSStatus playbackCallback(void *inRefCon, 
								 AudioUnitRenderActionFlags *ioActionFlags, 
								 const AudioTimeStamp *inTimeStamp, 
								 UInt32 inBusNumber, 
								 UInt32 inNumberFrames, 
								 AudioBufferList *ioData) {    
    // Notes: ioData contains buffers (may be more than one!)
    // Fill them up as much as you can. Remember to set the size value in each buffer to match how
    // much data is in the buffer.
	
	for (int i=0; i < ioData->mNumberBuffers; i++) { // in practice we will only ever have 1 buffer, since audio format is mono
		AudioBuffer buffer = ioData->mBuffers[i];
		
//		NSLog(@"  Buffer %d has %d channels and wants %d bytes of data.", i, buffer.mNumberChannels, buffer.mDataByteSize);
		
		// copy temporary buffer data to output buffer
		UInt32 size = min(buffer.mDataByteSize, [iosAudio tempBuffer].mDataByteSize); // dont copy more data then we have, or then fits
		memcpy(buffer.mData, [iosAudio tempBuffer].mData, size);
		buffer.mDataByteSize = size; // indicate how much data we wrote in the buffer
		
		// uncomment to hear random noise
		/*
		UInt16 *frameBuffer = buffer.mData;
		for (int j = 0; j < inNumberFrames; j++) {
			frameBuffer[j] = rand();
		}
		
		
	}
	
    return noErr;
}
*/
@implementation IosAudioController

@synthesize audioUnit, tempBuffer;

/**
 Initialize the audioUnit and allocate our own temporary buffer.
 The temporary buffer will hold the latest data coming in from the microphone,
 and will be copied to the output when this is requested.
 */

- (id) init {
	self = [super init];
    TPCircularBufferInit(&incomingCircularBuffer, 1024*10000);
	OSStatus status;
	
	// Describe audio component
	AudioComponentDescription desc;
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_RemoteIO;
	desc.componentFlags = 0;
	desc.componentFlagsMask = 0;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	
	// Get component
	AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
	
	// Get audio units
	status = AudioComponentInstanceNew(inputComponent, &audioUnit);
	
	// Enable IO for recording
    UInt32 flag = 1;
    UInt32 noFlag = 0;
	status = AudioUnitSetProperty(audioUnit,
								  kAudioOutputUnitProperty_EnableIO,
								  kAudioUnitScope_Input,
								  kInputBus,
								  &flag,
								  sizeof(flag));
    
	
	// Enable IO for playback
	status = AudioUnitSetProperty(audioUnit,
								  kAudioOutputUnitProperty_EnableIO,
								  kAudioUnitScope_Output,
								  kOutputBus,
								  &flag,
								  sizeof(flag));
	
	// Describe format
	AudioStreamBasicDescription audioFormat;
    bzero(&audioFormat, sizeof(AudioStreamBasicDescription));
    UInt32 channelCount = 2;
    UInt32 sampleSize = sizeof(UInt16);
	audioFormat.mSampleRate			= 44100.00;
	audioFormat.mFormatID			= kAudioFormatLinearPCM;
	audioFormat.mFormatFlags		= kAudioFormatFlagsCanonical;;
	audioFormat.mFramesPerPacket	= 1;
	audioFormat.mChannelsPerFrame	= channelCount;
	audioFormat.mBitsPerChannel		= sampleSize * 8;
	audioFormat.mBytesPerPacket		= sampleSize * channelCount;
	audioFormat.mBytesPerFrame		= sampleSize * channelCount;
	
	// Apply format
	status = AudioUnitSetProperty(audioUnit,
								  kAudioUnitProperty_StreamFormat,
								  kAudioUnitScope_Output,
								  kInputBus,
								  &audioFormat,
								  sizeof(audioFormat));
    
	status = AudioUnitSetProperty(audioUnit,
								  kAudioUnitProperty_StreamFormat,
								  kAudioUnitScope_Input,
								  kOutputBus,
								  &audioFormat,
								  sizeof(audioFormat));
    
	
	
	// Set input callback
	AURenderCallbackStruct callbackStruct;
	callbackStruct.inputProcRefCon = self;
	status = AudioUnitSetProperty(audioUnit,
								  kAudioOutputUnitProperty_SetInputCallback,
								  kAudioUnitScope_Global,
								  kInputBus,
								  &callbackStruct,
								  sizeof(callbackStruct));
    
	
	// Set output callback
	callbackStruct.inputProc = playbackCallback;
	callbackStruct.inputProcRefCon = self;
	status = AudioUnitSetProperty(audioUnit,
								  kAudioUnitProperty_SetRenderCallback,
								  kAudioUnitScope_Global,
								  kOutputBus,
								  &callbackStruct,
								  sizeof(callbackStruct));
    
	
	// Disable buffer allocation for the recorder (optional - do this if we want to pass in our own)
	flag = 0;
	status = AudioUnitSetProperty(audioUnit,
								  kAudioUnitProperty_ShouldAllocateBuffer,
								  kAudioUnitScope_Output,
								  kInputBus,
								  &flag,
								  sizeof(flag));
	
	// Allocate our own buffers (1 channel, 16 bits per sample, thus 16 bits per frame, thus 2 bytes per frame).
	// Practice learns the buffers used contain 512 frames, if this changes it will be fixed in processAudio.
	tempBuffer.mNumberChannels = 1;
	tempBuffer.mDataByteSize = 512 * 2;
	tempBuffer.mData = malloc( 512 * 2 );
	
	// Initialise
	status = AudioUnitInitialize(audioUnit);
    
	
	return self;
}


/**
 Start the audioUnit. This means data will be provided from
 the microphone, and requested for feeding to the speakers, by
 use of the provided callbacks.
 */
- (void) start {
	OSStatus status = AudioOutputUnitStart(audioUnit);
	checkStatus(status);
}

/**
 Stop the audioUnit
 */
- (void) stop {
	OSStatus status = AudioOutputUnitStop(audioUnit);
	checkStatus(status);
}

/**
 Change this funtion to decide what is done with incoming
 audio data from the microphone.
 Right now we copy it to our own temporary buffer.
 */
- (void) processAudio: (AudioBufferList*) bufferList{
	AudioBuffer sourceBuffer = bufferList->mBuffers[0];
	
	// fix tempBuffer size if it's the wrong size
	if (tempBuffer.mDataByteSize != sourceBuffer.mDataByteSize) {
		free(tempBuffer.mData);
		tempBuffer.mDataByteSize = sourceBuffer.mDataByteSize;
		tempBuffer.mData = malloc(sourceBuffer.mDataByteSize);
	}
	NSData *data = [[NSData alloc] initWithBytes:bufferList->mBuffers[0].mData length:1024];
    [self saveToFile:data];
	// copy incoming audio data to temporary buffer
	memcpy(tempBuffer.mData, bufferList->mBuffers[0].mData, bufferList->mBuffers[0].mDataByteSize);
}

#pragma mark - Buffer Debuggers methods
- (void)saveToFile:(NSData *)data{
    NSFileHandle *handle = [NSFileHandle fileHandleForUpdatingAtPath:@"/Users/peterfong/desktop/testrecord"];
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

- (void)loadDataFromFile{
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"testwav" ofType:@"wav"];
    NSData *data1 = [[NSFileManager defaultManager] contentsAtPath:filePath] ;
    

    for (int i = 0; i< ([data1 length]/2048); i++){
        NSData *newData = [data1 subdataWithRange:NSMakeRange(1024*i, 1023*(i+1))];
        TPCircularBufferProduceBytes(&iosAudio->incomingCircularBuffer, [newData bytes], 1024);
        iosAudio.pkgtotal += 1;
    }
}



/**
 Clean up.
 */
- (void) dealloc {
	[super	dealloc];
	AudioUnitUninitialize(audioUnit);
	free(tempBuffer.mData);
}

@end
