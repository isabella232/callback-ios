//
//  PGLightViewController.h
//
//  Created by Todd Stellanova on 12/5/11.
//  Copyright (c) 2011 Salesforce.com. All rights reserved.
//

#import <UIKit/UIKit.h>

@class InvokedUrlCommand;
@class PGWhitelist;

@interface PGLightViewController : UIViewController <UIWebViewDelegate> {
    
    UIWebView *_webView;
    NSArray *_supportedOrientations;
    NSDictionary *_settings;
    NSString *_gapSessionKey;
    PGWhitelist *_hostWhitelist;
    NSString *_startPage;
    
}

@property (nonatomic, copy) 	NSArray *supportedOrientations;
@property (nonatomic, retain)	UIWebView *webView;
@property (nonatomic, readonly, retain) NSDictionary *settings;
@property (nonatomic, readwrite, retain) NSString *gapSessionKey; 
@property (nonatomic, readwrite, retain) PGWhitelist* hostWhitelist; 

@property (nonatomic, retain) NSString *startPage;
@property (nonatomic, retain) NSString *wwwFolderName;
@property (readwrite, assign) BOOL loadFromString;


#pragma mark - Embedded UIWebView management

/**
 Tear down the existing web view.
 @see reinitializeWebView
 */
- (void)teardownWebView;

/**
 (re)Initialize the embedded web view.
 @see teardownWebView
 */
- (void)reinitializeWebView;

/**
 Load the start page into the embedded web view.
 */
- (void)loadStartPageIntoWebView;


/**
 Configure the web view from self.settings.
 @param aWebView The web view to configure;
 */
- (void)configureWebViewFromSettings:(UIWebView*)aWebView;

- (void)showHTMLError:(NSString*)errorString;


#pragma mark - Command Queue

- (int)executeQueuedCommands;
- (void)flushCommandQueue;
- (BOOL)execute:(InvokedUrlCommand*)command;


#pragma mark - Public

- (NSString*) pathForResource:(NSString*)resourcePath;


/**
 Force a javascript alert to be shown in the embedded UIWebView
 @param text  Message to be shown in the web view in a javascript alert.
 */
- (void) javascriptAlert:(NSString*)text;


@end
