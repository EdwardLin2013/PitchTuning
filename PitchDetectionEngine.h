//
//  PitchDetectionEngine.h
//  PitchTuning
//
//  Created by Edward on 27/11/13.
//  Copyright (c) 2013 Edward. All rights reserved.
//

// Force to Commit to Github
#import <Foundation/Foundation.h>
#import <AudioUnit/AudioUnit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>

/**
 *	This is a singleton class that manages all the low level CoreAudio/RemoteIO
 *	elements. A singleton is used since we should never be instantiating more
 *  than one instance of this class per application lifecycle.
 */

#define kInputBus 1                                 // Audio Unit Element
#define kOutputBus 0                                // Audio Unit Element
#define kBufferSize 1024                            // Default: 1024 samples, 2 bytes(16bits) per sample

@interface PitchDetectionEngine : NSObject
{
	AUGraph processingGraph;                    // Audio Unit Processing Graph
	AudioUnit ioUnit;                           // Microphone
	AudioBufferList* bufferList;                // Buffer for 1 frame, 1 frame = 1024samples
	AudioStreamBasicDescription streamFormat;   // Sample Rate: 44100, bytes per sample: 2 bytes

	FFTSetup fftSetup;                          // vDSP_create_fftsetup(log2n, FF_RADIX2)
	COMPLEX_SPLIT FFT;                          // Convert from outputBuffer to split complex vector
    COMPLEX_SPLIT Cepstrum;
	int log2n, n, nOver2;                       // default: 11, 2048, 1024
	
	void *dataBuffer;                           // Buffer for Obtaining data from Microphone Audio Unit
	float *outputBuffer;                        // Convert from dataBuffer, but still in interleaved Complex vector
                                                // After FFT, convert back from A(in frequency value),
                                                // and find the pitch
	size_t index;                               // Current buffer usage of dataBuffer
    size_t bufferCapacity;                      // default: 2048 (bytes) as 2 bytes per sample
    
	float sampleRate;                           // default: 44100
}

/* Setup the singleton Engine */
+ (id)sharedEngine;
- (id)init;

/* Initialize Audio Session - Setup Sample Rate, Specify the Stream Format and FFT Setup */
- (void)initializeAudioSession;
- (size_t)ASBDForSoundMode;
- (void)realFFTSetup;

/* Setup the microphone and attach it with analysis callback function */
- (void)createAUProcessingGraph;

/* Turn on the microphone */
- (void)initializeAndStartProcessingGraph;

/* For Debug Only */
- (void)printPitchDetectionEngine;
- (void)printASBD:(AudioStreamBasicDescription)asbd;

@end
