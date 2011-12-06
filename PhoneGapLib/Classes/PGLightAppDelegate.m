/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 * 
 * Copyright (c) 2005-2010, Nitobi Software Inc.
 * Copyright (c) 2010, IBM Corporation
 */

//  Created by Todd Stellanova on 12/5/11.
//  Copyright (c) 2011 Salesforce.com. All rights reserved.

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

#import "Location.h"
#import "Sound.h"
#import "DebugConsole.h"
#import "Connection.h"

#import "PGURLProtocol.h"
#import "PGWhitelist.h"
#import "InvokedUrlCommand.h"
#import "PGLightAppDelegate.h"
#import "PGPlugin.h"

#define SYMBOL_TO_NSSTRING_HELPER(x) @#x
#define SYMBOL_TO_NSSTRING(x) SYMBOL_TO_NSSTRING_HELPER(x)

#define degreesToRadian(x) (M_PI * (x) / 180.0)


NSString * const kAppPlistName =  @"PhoneGap";
NSString * const kAppPlist_PluginsKey = @"Plugins";

static NSString *gapVersion;


@interface NSDictionary (LowercaseKeys)

- (NSMutableDictionary*) dictionaryWithLowercaseKeys;

@end

// class extension
@interface PGLightAppDelegate ()

// readwrite access for self

@property (nonatomic, readwrite, retain) IBOutlet UIActivityIndicatorView *activityView;
@property (nonatomic, readwrite, retain) UIImageView *imageView;

@property (nonatomic, readwrite, retain) NSMutableDictionary *pluginsMap;
@property (nonatomic, readwrite, retain) NSMutableDictionary *pluginObjects;

@property (nonatomic, readwrite, retain) NSDictionary *settings;
@property (nonatomic, readwrite, retain) NSURL *invokedURL;

@property (readwrite, assign) UIInterfaceOrientation orientationType;

@property (nonatomic, readwrite, retain) PGWhitelist* whitelist; 


+ (NSString*) resolveImageResource:(NSString*)resource;

@end


@implementation PGLightAppDelegate

@synthesize window, activityView, imageView;
@synthesize settings, invokedURL, orientationType;
@synthesize pluginObjects = _pluginObjects, pluginsMap = _pluginsMap, whitelist;

- (id) init
{
    self = [super init];
    if (self != nil) {
        _pluginObjects = [[NSMutableDictionary alloc] initWithCapacity:4];
        self.imageView = nil;
        
        // Turn on cookie support ( shared with our app only! )
        NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage]; 
        [cookieStorage setCookieAcceptPolicy:NSHTTPCookieAcceptPolicyAlways];
        
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receivedOrientationChange) name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
        
        [PGURLProtocol registerPGHttpURLProtocol];
    }
    return self; 
}


- (void)dealloc
{
    [PluginResult releaseStatus];
    self.pluginObjects = nil;
    self.pluginsMap    = nil;
    
    self.activityView = nil;
    
    self.window = nil;
    self.imageView = nil;
    self.whitelist = nil;
    
    [super dealloc];
}


+ (PGLightAppDelegate*)sharedInstance
{
    return (PGLightAppDelegate*)[[UIApplication sharedApplication] delegate];
}

+ (NSString*)applicationDocumentsDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}



+ (BOOL) isIPad 
{
#ifdef UI_USER_INTERFACE_IDIOM
    return (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
#else
    return NO;
#endif
}



/**
Returns the current version of phoneGap as read from the VERSION file
This only touches the filesystem once and stores the result in the class variable gapVersion
*/
+ (NSString*) phoneGapVersion
{
#ifdef PG_VERSION
    gapVersion = SYMBOL_TO_NSSTRING(PG_VERSION);
#else
    if (gapVersion == nil) {
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *filename = [mainBundle pathForResource:@"VERSION" ofType:nil];
        // read from the filesystem and save in the variable
        // first, separate by new line
        NSString* fileContents = [NSString stringWithContentsOfFile:filename encoding:NSUTF8StringEncoding error:NULL];
        NSArray* all_lines = [fileContents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSString* first_line = [all_lines objectAtIndex:0];        
        
        gapVersion = [first_line retain];
    }
#endif
    
    return gapVersion;
}



- (NSArray*) parseInterfaceOrientations:(NSArray*)orientations
{
    NSMutableArray* result = [[[NSMutableArray alloc] init] autorelease];

    if (orientations != nil) 
    {
        NSEnumerator* enumerator = [orientations objectEnumerator];
        NSString* orientationString;
        
        while (orientationString = [enumerator nextObject]) 
        {
            if ([orientationString isEqualToString:@"UIInterfaceOrientationPortrait"]) {
                [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationPortrait]];
            } else if ([orientationString isEqualToString:@"UIInterfaceOrientationPortraitUpsideDown"]) {
                [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationPortraitUpsideDown]];
            } else if ([orientationString isEqualToString:@"UIInterfaceOrientationLandscapeLeft"]) {
                [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationLandscapeLeft]];
            } else if ([orientationString isEqualToString:@"UIInterfaceOrientationLandscapeRight"]) {
                [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationLandscapeRight]];
            }
        }
    }
    
    // default
    if ([result count] == 0) {
        [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationPortrait]];
    }
    
    return result;
}


#pragma mark - SplashScreen Management

- (void) showSplashScreen
{
    NSString* launchImageFile = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"UILaunchImageFile"];
    if (launchImageFile == nil) { // fallback if no launch image was specified
        launchImageFile = @"Default"; 
    }
    
    NSString* orientedLaunchImageFile = nil;    
    CGAffineTransform startupImageTransform = CGAffineTransformIdentity;
    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
    BOOL isIPad = [[self class] isIPad];
    UIImage* launchImage = nil;
    
    if (isIPad)
    {
        if (!UIDeviceOrientationIsValidInterfaceOrientation(deviceOrientation)) {
            deviceOrientation = (UIDeviceOrientation)statusBarOrientation;
        }
        
        switch (deviceOrientation) 
        {
            case UIDeviceOrientationLandscapeLeft: // this is where the home button is on the right (yeah, I know, confusing)
            {
                orientedLaunchImageFile = [NSString stringWithFormat:@"%@-Landscape", launchImageFile];
                startupImageTransform = CGAffineTransformMakeRotation(degreesToRadian(90));
            }
                break;
            case UIDeviceOrientationLandscapeRight: // this is where the home button is on the left (yeah, I know, confusing)
            {
                orientedLaunchImageFile = [NSString stringWithFormat:@"%@-Landscape", launchImageFile];
                startupImageTransform = CGAffineTransformMakeRotation(degreesToRadian(-90));
            } 
                break;
            case UIDeviceOrientationPortraitUpsideDown:
            {
                orientedLaunchImageFile = [NSString stringWithFormat:@"%@-Portrait", launchImageFile];
                startupImageTransform = CGAffineTransformMakeRotation(degreesToRadian(180));
            } 
                break;
            case UIDeviceOrientationPortrait:
            default:
            {
                orientedLaunchImageFile = [NSString stringWithFormat:@"%@-Portrait", launchImageFile];
                startupImageTransform = CGAffineTransformIdentity;
            }
                break;
        }
        
        launchImage = [UIImage imageNamed:[[self class] resolveImageResource:orientedLaunchImageFile]];
    }
    else // not iPad
    {
        orientedLaunchImageFile = @"Default";
        launchImage = [UIImage imageNamed:[[self class] resolveImageResource:orientedLaunchImageFile]];
    }
    
    if (launchImage == nil) {
        NSLog(@"WARNING: Splash-screen image '%@' was not found. Orientation: %d, iPad: %d", orientedLaunchImageFile, deviceOrientation, isIPad);
    }
    
    self.imageView = [[[UIImageView alloc] initWithImage:launchImage] autorelease];    
    self.imageView.tag = 1;
    self.imageView.center = CGPointMake((screenBounds.size.width / 2), (screenBounds.size.height / 2));
    
    self.imageView.autoresizingMask = (UIViewAutoresizingFlexibleWidth & UIViewAutoresizingFlexibleHeight & UIViewAutoresizingFlexibleLeftMargin & UIViewAutoresizingFlexibleRightMargin);    
    [self.imageView setTransform:startupImageTransform];
    [self.window addSubview:self.imageView];
    
    
    /*
     * The Activity View is the top spinning throbber in the status/battery bar. We init it with the default Grey Style.
     *
     *     whiteLarge = UIActivityIndicatorViewStyleWhiteLarge
     *     white      = UIActivityIndicatorViewStyleWhite
     *     gray       = UIActivityIndicatorViewStyleGray
     *
     */
    NSString *topActivityIndicator = [self.settings objectForKey:@"TopActivityIndicator"];
    UIActivityIndicatorViewStyle topActivityIndicatorStyle = UIActivityIndicatorViewStyleGray;
    
    if ([topActivityIndicator isEqualToString:@"whiteLarge"]) {
        topActivityIndicatorStyle = UIActivityIndicatorViewStyleWhiteLarge;
    } else if ([topActivityIndicator isEqualToString:@"white"]) {
        topActivityIndicatorStyle = UIActivityIndicatorViewStyleWhite;
    } else if ([topActivityIndicator isEqualToString:@"gray"]) {
        topActivityIndicatorStyle = UIActivityIndicatorViewStyleGray;
    }
    
    self.activityView = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:topActivityIndicatorStyle] autorelease];
    self.activityView.tag = 2;

    id showSplashScreenSpinnerValue = [self.settings objectForKey:@"ShowSplashScreenSpinner"];
    // backwards compatibility - if key is missing, default to true
    if (showSplashScreenSpinnerValue == nil || [showSplashScreenSpinnerValue boolValue]) {
        [self.window addSubview:self.activityView];
    }
    
    //TODO
    
    //self.activityView.center = self.viewController.view.center;
    [self.activityView startAnimating];
    
    
    [self.window layoutSubviews];//asking window to do layout AFTER imageView is created refer to line: 250     self.window.autoresizesSubviews = YES;
}    

- (void) receivedOrientationChange
{
    if (self.imageView == nil) {
        [self showSplashScreen];
    }
}


+ (NSString*) resolveImageResource:(NSString*)resource
{
    NSString* systemVersion = [[UIDevice currentDevice] systemVersion];
    BOOL isLessThaniOS4 = ([systemVersion compare:@"4.0" options:NSNumericSearch] == NSOrderedAscending);
    
    // the iPad image (nor retina) differentiation code was not in 3.x, and we have to explicitly set the path
    if (isLessThaniOS4)
    {
        if ([[self class] isIPad]) {
            return [NSString stringWithFormat:@"%@~ipad.png", resource];
        } else {
            return [NSString stringWithFormat:@"%@.png", resource];
        }
    }
    
    return resource;
}


#pragma mark - Plugins Management


/**
 Returns an instance of a PhoneGapCommand object, based on its name.  If one exists already, it is returned.
 */
-(id) getCommandInstance:(NSString*)pluginName
{
    //TODO muster  up a web view
    id obj = [self getCommandInstance:pluginName forWebView:nil];
    
    return obj;
}


-(id) getCommandInstance:(NSString*)pluginName forWebView:(UIWebView*)aWebView
{
    // first, we try to find the pluginName in the pluginsMap 
    // (acts as a whitelist as well) if it does not exist, we return nil
    // NOTE: plugin names are matched as lowercase to avoid problems - however, a 
    // possible issue is there can be duplicates possible if you had:
    // "com.phonegap.Foo" and "com.phonegap.foo" - only the lower-cased entry will match
    NSString* className = [self.pluginsMap objectForKey:[pluginName lowercaseString]];
    if (className == nil) {
        return nil;
    }
    
    id obj = [self.pluginObjects objectForKey:className];
    if (!obj) 
    {
        // attempt to load the settings for this command class
        NSDictionary* classSettings = [self.settings objectForKey:className];
        
        //TODO if aWebView is nil, find the first visible web view?
        
        if (classSettings) {
            obj = [[NSClassFromString(className) alloc] initWithWebView:aWebView settings:classSettings];
        } else {
            obj = [[NSClassFromString(className) alloc] initWithWebView:aWebView];
        }
        
        if (obj != nil) {
            [self.pluginObjects setObject:obj forKey:className];
            [obj release];
        } else {
            NSLog(@"PGPlugin class %@ (pluginName: %@) does not exist.", className, pluginName);
        }
    }
    return obj;
}

- (void)reinitializePlugins
{
    NSLog(@"reinitializePlugins");
    // read from Plugins dict in PhoneGap.plist in the app bundle
    NSDictionary* pluginsDict = [self.settings objectForKey:kAppPlist_PluginsKey];
    if (pluginsDict == nil) {
        NSLog(@"WARNING: %@ key in %@.plist is missing! PhoneGap will not work, you need to have this key.", kAppPlist_PluginsKey, kAppPlistName);
        NSAssert(nil != pluginsDict,@"Plugins key required in plist");
    }
    
    self.pluginObjects = nil;
    self.pluginsMap = nil;
    
    //reinit the plugins class map
    self.pluginsMap = [pluginsDict dictionaryWithLowercaseKeys];
    //reinit the plugins instance map
    _pluginObjects = [[NSMutableDictionary alloc] initWithCapacity:4];
    
    //setup the Location plugin
    //Fire up the GPS Service right away as it takes a moment for data to come back.
    BOOL enableLocation   = [[self.settings objectForKey:@"EnableLocation"] boolValue];    
    if (enableLocation) {
        [[self getCommandInstance:@"com.phonegap.geolocation"] startLocation:nil withDict:nil];
    }
    
}




- (NSDictionary*) deviceProperties
{
    UIDevice *device = [UIDevice currentDevice];
    NSMutableDictionary *devProps = [NSMutableDictionary dictionaryWithCapacity:4];
    [devProps setObject:[device model] forKey:@"platform"];
    [devProps setObject:[device systemVersion] forKey:@"version"];
    [devProps setObject:[device uniqueIdentifier] forKey:@"uuid"];
    [devProps setObject:[device name] forKey:@"name"];
    [devProps setObject:[[self class] phoneGapVersion ] forKey:@"gap"];
    
    id cmd = [self getCommandInstance:@"com.phonegap.connection"];
    if (cmd && [cmd isKindOfClass:[PGConnection class]]) 
    {
        NSMutableDictionary *connProps = [NSMutableDictionary dictionaryWithCapacity:3];
        if ([cmd respondsToSelector:@selector(connectionType)]) {
            [connProps setObject:[cmd connectionType] forKey:@"type"];
        }
        [devProps setObject:connProps forKey:@"connection"];
    }
    
    NSDictionary *devReturn = [NSDictionary dictionaryWithDictionary:devProps];
    return devReturn;
}

- (NSString*) appURLScheme
{
    NSString* URLScheme = nil;
    
    NSArray *URLTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleURLTypes"];
    if(URLTypes != nil ) {
        NSDictionary* dict = [URLTypes objectAtIndex:0];
        if(dict != nil ) {
            NSArray* URLSchemes = [dict objectForKey:@"CFBundleURLSchemes"];
            if( URLSchemes != nil ) {    
                URLScheme = [URLSchemes objectAtIndex:0];
            }
        }
    }
    
    return URLScheme;
}



/**
 Returns the contents of the named plist bundle, loaded as a dictionary object
 */
+ (NSDictionary*)getBundlePlist:(NSString *)plistName
{
    NSString *errorDesc = nil;
    NSPropertyListFormat format;
    NSString *plistPath = [[NSBundle mainBundle] pathForResource:plistName ofType:@"plist"];
    NSData *plistXML = [[NSFileManager defaultManager] contentsAtPath:plistPath];
    NSDictionary *temp = (NSDictionary *)[NSPropertyListSerialization
                                          propertyListFromData:plistXML
                                          mutabilityOption:NSPropertyListMutableContainersAndLeaves              
                                          format:&format errorDescription:&errorDesc];
    return temp;
}


#pragma mark - App Lifecycle

/**
 * This is main kick off after the app inits, the views and Settings are setup here.
 */
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSDictionary *settingsDict = [[self class] getBundlePlist:kAppPlistName];
    self.settings = settingsDict;
    
    [self reinitializePlugins];
    
    // set the external hosts whitelist
    PGWhitelist *hostWhitelist = [[PGWhitelist alloc] initWithArray:[settingsDict objectForKey:@"ExternalHosts"]];
    self.whitelist = hostWhitelist;
    [hostWhitelist release];
    

    //TODO setup a default view controller
    
    [self.window makeKeyAndVisible];
    
    
    return YES;
    
}


/*
 This method lets your application know that it is about to be terminated and purged from memory entirely
*/
- (void)applicationWillTerminate:(UIApplication *)application
{
    NSLog(@"applicationWillTerminate");
    
    // empty the tmp directory
    NSFileManager* fileMgr = [[NSFileManager alloc] init];
    NSError* err = nil;    

    // clear contents of NSTemporaryDirectory 
    NSString* tempDirectoryPath = NSTemporaryDirectory();
    NSDirectoryEnumerator* directoryEnumerator = [fileMgr enumeratorAtPath:tempDirectoryPath];    
    NSString* fileName = nil;
    BOOL result;
    
    while ((fileName = [directoryEnumerator nextObject])) {
        NSString* filePath = [tempDirectoryPath stringByAppendingPathComponent:fileName];
        result = [fileMgr removeItemAtPath:filePath error:&err];
        if (!result && err) {
            NSLog(@"Failed to delete: %@ (error: %@)", filePath, err);
        }
    }    
    [fileMgr release];
}

/*
 This method is called to let your application know that it is about to move from the active to inactive state.
 You should use this method to pause ongoing tasks, disable timer, ...
*/
- (void)applicationWillResignActive:(UIApplication *)application
{
    NSLog(@"%@",@"applicationWillResignActive");
    //TODO push event to all child VCs
    //[self.webView stringByEvaluatingJavaScriptFromString:@"PhoneGap.fireDocumentEvent('resign');"];
}

/*
 In iOS 4.0 and later, this method is called as part of the transition from the background to the inactive state. 
 You can use this method to undo many of the changes you made to your application upon entering the background.
 invariably followed by applicationDidBecomeActive
*/
- (void)applicationWillEnterForeground:(UIApplication *)application
{
    NSLog(@"%@",@"applicationWillEnterForeground");
    //TODO push event to all child VCs
    //[self.webView stringByEvaluatingJavaScriptFromString:@"PhoneGap.fireDocumentEvent('resume');"];
}

// This method is called to let your application know that it moved from the inactive to active state. 
- (void)applicationDidBecomeActive:(UIApplication *)application
{
    NSLog(@"%@",@"applicationDidBecomeActive");
    //TODO push event to all child VCs
    //[self.webView stringByEvaluatingJavaScriptFromString:@"PhoneGap.fireDocumentEvent('active');"];
}

/*
 In iOS 4.0 and later, this method is called instead of the applicationWillTerminate: method 
 when the user quits an application that supports background execution.
 */
- (void)applicationDidEnterBackground:(UIApplication *)application
{
    NSLog(@"%@",@"applicationDidEnterBackground");
    //TODO push event to all child VCs
    //[self.webView stringByEvaluatingJavaScriptFromString:@"PhoneGap.fireDocumentEvent('pause');"];
}


/*
 Determine the URL passed to this application.
 Described in http://iphonedevelopertips.com/cocoa/launching-your-own-application-via-a-custom-url-scheme.html
*/
- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
    if (!url) { 
        return NO; 
    }

    //TODO
    
    /*
    // Do something with the url here
    NSString* jsString = [NSString stringWithFormat:@"handleOpenURL(\"%@\");", url];
    [self.webView stringByEvaluatingJavaScriptFromString:jsString];
    
    [[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:PGPluginHandleOpenURLNotification object:url]];
     */
    
    return YES;
}



@end

@implementation NSDictionary (LowercaseKeys)

- (NSMutableDictionary*) dictionaryWithLowercaseKeys 
{
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithCapacity:self.count];
    NSString* key;
    
    for (key in self) {
        [result setObject:[self objectForKey:key] forKey:[key lowercaseString]];
    }
    
    return result;
}

@end
