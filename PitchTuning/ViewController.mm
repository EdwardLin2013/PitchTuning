//
//  ViewController.m
//  PitchTuning
//
//  Created by Edward on 26/11/13.
//  Copyright (c) 2013 Edward. All rights reserved.
//
// Force to Commit to Github

#import "ViewController.h"

@interface ViewController ()
{
    PitchDetectionEngine *Engine;
}
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    /*
     *  Start Pitch Detection Engine (Singleton), which includes
     *  1) Setup the Mic
     *  2) Analysis whatever sound comes from the Mic
     *  3) ? Store the Pitch Record? 
     */
    Engine = [PitchDetectionEngine sharedEngine];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
