/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 * 
 * Copyright (c) 2005-2010, Nitobi Software Inc.
 * Copyright (c) 2010, IBM Corporation
 */


#import <UIKit/UIKit.h>
#import "JSONKit.h"

@class InvokedUrlCommand;
@class Sound;
@class Contacts;
@class Console;
@class PGWhitelist;

@interface PGLightAppDelegate : NSObject <UIApplicationDelegate>
{

}


@property (nonatomic, readwrite, retain) IBOutlet UIWindow *window;

@property (nonatomic, readonly, retain) IBOutlet UIActivityIndicatorView *activityView;
@property (nonatomic, readonly, retain) UIImageView *imageView;

@property (nonatomic, readonly, retain) NSMutableDictionary *pluginObjects;
@property (nonatomic, readonly, retain) NSMutableDictionary *pluginsMap;
@property (nonatomic, readonly, retain) NSDictionary *settings;
@property (nonatomic, readonly, retain) PGWhitelist* whitelist; // readonly for public


#pragma mark - App settings 


+ (PGLightAppDelegate*)sharedInstance;

+ (NSDictionary*)getBundlePlist:(NSString *)plistName;
+ (NSString*) phoneGapVersion;
+ (NSString*) applicationDocumentsDirectory;




/**
 @return NSString The first URL scheme supported by this app, if any registered with CFBundleURLSchemes in the app .plist
 */
- (NSString*) appURLScheme;

/**
 @return NSDictionary A set of device and app properties
 */
- (NSDictionary*) deviceProperties;



#pragma mark - Plugin Management

/**
 
 */
- (void)reinitializePlugins;

/**
 Get an instance of the named plugin.  This method creates a new instance if
 one does not already exist. If there is an existing instance, this method returns it.
 Thus, plugins are essentially singletons.
 
 @param pluginName Class name for plugin, eg "com.salesforce.com.foo"
 @return Singleton instance of the named plugin
 */
- (id) getCommandInstance:(NSString*)pluginName;


-(id) getCommandInstance:(NSString*)pluginName forWebView:(UIWebView*)webView;




#pragma mark - Public

+ (BOOL) isIPad;




@end


