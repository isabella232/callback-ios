//
//  PGLightViewController.m
//  FatStack
//
//  Created by Todd Stellanova on 12/5/11.
//  Copyright (c) 2011 Salesforce.com. All rights reserved.
//

#import "PGLightViewController.h"

#import "InvokedUrlCommand.h"
#import "JSONKit.h"
#import "PGLightAppDelegate.h"
#import "PGPlugin.h"
#import "PGWhitelist.h"

@implementation PGLightViewController

@synthesize supportedOrientations = _supportedOrientations;
@synthesize webView = _webView;
@synthesize settings = _settings;
@synthesize gapSessionKey = _gapSessionKey;
@synthesize hostWhitelist = _hostWhitelist;
@synthesize loadFromString = _loadFromString;
@synthesize startPage = _startPage;

@synthesize wwwFolderName = _wwwFolderName;


- (id)init {
    
    self = [super init];
    
    if (nil != self) {
        // Create the sessionKey to use throughout the lifetime of the application
        // to authenticate the source of the gap calls
        self.gapSessionKey = [NSString stringWithFormat:@"%d", arc4random()];
    }
    
    return self;
}
#pragma mark - Embedded UIWebView management


- (void)teardownWebView {
    NSLog(@"teardownWebView");
    [self.webView setDelegate:nil];
    self.webView = nil;

}

- (void)configureWebViewFromSettings:(UIWebView*)aWebView
{
    NSLog(@"configureWebViewFromSettings");
    
    //configure the web view
    BOOL enableViewportScale = [[self.settings objectForKey:@"EnableViewportScale"] boolValue];
    BOOL allowInlineMediaPlayback = [[self.settings objectForKey:@"AllowInlineMediaPlayback"] boolValue];
    BOOL mediaPlaybackRequiresUserAction = [[self.settings objectForKey:@"MediaPlaybackRequiresUserAction"] boolValue];
    
    
    aWebView.scalesPageToFit = enableViewportScale;
    
    if (allowInlineMediaPlayback && [aWebView respondsToSelector:@selector(allowsInlineMediaPlayback)]) {
        aWebView.allowsInlineMediaPlayback = YES;
    }
    
    if (mediaPlaybackRequiresUserAction && [aWebView respondsToSelector:@selector(mediaPlaybackRequiresUserAction)]) {
        aWebView.mediaPlaybackRequiresUserAction = YES;
    }
    
}

- (void)reinitializeWebView
{
    
    NSLog(@"reinitializeWebView");
    
    
    
    //create and configure a new UIWebView
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
//    UIWindow *newWindow =  [[UIWindow alloc] initWithFrame:screenBounds ];
//    self.window = newWindow;
//    [newWindow release];
    
    CGRect webViewBounds = [[UIScreen mainScreen] applicationFrame] ;
    webViewBounds.origin = screenBounds.origin;
    UIWebView *newWebView = [[UIWebView alloc ] initWithFrame:webViewBounds];
    newWebView.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    [self configureWebViewFromSettings:newWebView];
    self.webView = newWebView;
    [self.webView setDelegate:self];
    
//    //create a new root view controller
//    PhoneGapViewController *vc = [[PhoneGapViewController alloc] init];
//    vc.supportedOrientations = supportedOrientations;
//    vc.webView = newWebView;//setting this property now automatically adds the web view as a subview of the vc view
//    [newWebView release];

    
    //[self.window addSubview:self.viewController.view];
//    [self.window setRootViewController:self.viewController];
    
}


- (void)loadStartPageIntoWebView
{
    NSLog(@"loadStartPageIntoWebView");
    
    NSString *startPage = [self startPage]; 
    NSURL *appURL = [NSURL URLWithString:startPage];
    NSString *loadErr = nil;
    
    if (nil == [appURL scheme]) {
        NSString* startFilePath = [self pathForResource:startPage];
        if (nil == startFilePath) {
            loadErr = [NSString stringWithFormat:@"ERROR: Start Page at '%@/%@' was not found.", self.wwwFolderName, startPage];
            NSLog(@"%@", loadErr);
            appURL = nil;
        }
        else {
            appURL = [NSURL fileURLWithPath:startFilePath];
        }
    }
    
    if (nil == loadErr) {
        NSLog(@"loading appURL: %@",appURL);
        //TODO make timeoutInterval and cachePolicy configurable?
        NSURLRequest *appReq = [NSURLRequest requestWithURL:appURL 
                                                cachePolicy:NSURLRequestUseProtocolCachePolicy 
                                            timeoutInterval:20.0];
        [self.webView loadRequest:appReq];
    } else {
        [self showHTMLError:loadErr];
    }
}

- (void)showHTMLError:(NSString*)errorString
{
    NSString* html = [NSString stringWithFormat:@"<html><body> %@ </body></html>", errorString];
    [self.webView loadHTMLString:html baseURL:nil];
    //self.loadFromString = YES;
}


#pragma mark - UIWebViewDelegate

/**
 * Start Loading Request
 * This is where most of the magic happens... We take the request(s) and process the response.
 * From here we can re direct links and other protocalls to different internal methods.
 *
 */
- (BOOL)webView:(UIWebView *)aWebView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSURL *url = [request URL];
    
    /*
     * Execute any commands queued with PhoneGap.exec() on the JS side.
     * The part of the URL after gap:// is irrelevant.
     */
    if ([[url scheme] isEqualToString:@"gap"]) {
        [self flushCommandQueue];
        return NO;
    }
    /*
     * If a URL is being loaded that's a file/http/https URL, just load it internally
     */
    else if ([url isFileURL])
    {
        return YES;
    }
    else if ([self.hostWhitelist schemeIsAllowed:[url scheme]])
    {            
        if ([self.hostWhitelist URLIsAllowed:url] == YES)
        {
            NSNumber *openAllInWhitelistSetting = [self.settings objectForKey:@"OpenAllWhitelistURLsInWebView"];
            if ((nil != openAllInWhitelistSetting) && [openAllInWhitelistSetting boolValue]) {
                NSLog(@"OpenAllWhitelistURLsInWebView set: opening in webview");
                return YES;
            }
            
            // mainDocument will be nil for an iFrame
            NSString* mainDocument = [self.webView.request.mainDocumentURL absoluteString];
            
            // anchor target="_blank" - load in Mobile Safari
            if (navigationType == UIWebViewNavigationTypeOther && mainDocument != nil)
            {
                [[UIApplication sharedApplication] openURL:url];
                return NO;
            }
            // other anchor target - load in PhoneGap webView
            else
            {
                return YES;
            }
        }
        
        return NO;
    }
    /*
     *    If we loaded the HTML from a string, we let the app handle it
     */
    else if (self.loadFromString == YES)
    {
        self.loadFromString = NO;
        return YES;
    }
    /*
     * all tel: scheme urls we let the UIWebview handle it using the default behaviour
     */
    else if ([[url scheme] isEqualToString:@"tel"])
    {
        return YES;
    }
    /*
     * all about: scheme urls are not handled
     */
    else if ([[url scheme] isEqualToString:@"about"])
    {
        return NO;
    }
    /*
     * We don't have a PhoneGap or web/local request, load it in the main Safari browser.
     * pass this to the application to handle.  Could be a mailto:dude@duderanch.com or a tel:55555555 or sms:55555555 facetime:55555555
     */
    else
    {
        NSLog(@"PhoneGapDelegate::shouldStartLoadWithRequest: Received Unhandled URL %@", url);
        
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url];
        } else { 
            //TODO // handle any custom schemes to plugins ??
        }
        
        return NO;
    }
    
    return YES;
}


/**
 When web application loads Add stuff to the DOM, mainly the user-defined settings from the Settings.plist file, and
 the device's data such as device ID, platform version, etc.
 */
- (void)webViewDidStartLoad:(UIWebView *)aWebView 
{
    
}

/**
 Called when the webview finishes loading.  This stops the activity view and closes the imageview
 */
- (void)webViewDidFinishLoad:(UIWebView *)aWebView 
{
    // Share session key with the WebView by setting PhoneGap.sessionKey
    NSString *sessionKeyScript = [NSString stringWithFormat:@"PhoneGap.sessionKey = \"%@\";", self.gapSessionKey];
    [aWebView stringByEvaluatingJavaScriptFromString:sessionKeyScript];
    
    
    NSDictionary *deviceProperties = [[PGLightAppDelegate sharedInstance] deviceProperties];
    
    NSMutableString *result = [[NSMutableString alloc] initWithFormat:@"DeviceInfo = %@;", [deviceProperties JSONString]];
    
    /* Settings.plist
     * Read the optional Settings.plist file and push these user-defined settings down into the web application.
     * This can be useful for supplying build-time configuration variables down to the app to change its behaviour,
     * such as specifying Full / Lite version, or localization (English vs German, for instance).
     */
    
    //TODO how to handle multiple settings on multiple views?
//    
//    NSDictionary *temp = [[self class] getBundlePlist:@"Settings"];
//    if ([temp respondsToSelector:@selector(JSONString)]) {
//        [result appendFormat:@"\nwindow.Settings = %@;", [temp JSONString]];
//    }
    
    NSLog(@"Device initialization: %@", result);
    [aWebView stringByEvaluatingJavaScriptFromString:result];
    [result release];
    
    /*
     * Hide the Top Activity THROBBER in the Battery Bar
     */
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    
    id autoHideSplashScreenValue = [self.settings objectForKey:@"AutoHideSplashScreen"];
    // if value is missing, default to yes
    if (autoHideSplashScreenValue == nil || [autoHideSplashScreenValue boolValue]) {
//        self.imageView.hidden = YES;
//        self.activityView.hidden = YES;    

//        [self.window bringSubviewToFront:self.viewController.view];
    }
    
    //TODO wtf:
    
//    [self.viewController didRotateFromInterfaceOrientation:(UIInterfaceOrientation)[[UIDevice currentDevice] orientation]];
}

/**
 * Fail Loading With Error
 * Error - If the webpage failed to load display an error with the reason.
 *
 */
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    NSLog(@"Failed to load webpage with error: %@", [error localizedDescription]);
    /*
     if ([error code] != NSURLErrorCancelled)
     alert([error localizedDescription]);
     */
}


#pragma mark - Command Queue

/**
 * Repeatedly fetches and executes the command queue until it is empty.
 */
- (void)flushCommandQueue
{
    [self.webView stringByEvaluatingJavaScriptFromString:
     @"PhoneGap.commandQueueFlushing = true"];
    
    // Keep executing the command queue until no commands get executed.
    // This ensures that commands that are queued while executing other
    // commands are executed as well.
    int numExecutedCommands = 0;
    do {
        numExecutedCommands = [self executeQueuedCommands];
    } while (numExecutedCommands != 0);
    
    [self.webView stringByEvaluatingJavaScriptFromString:
     @"PhoneGap.commandQueueFlushing = false"];
}

/**
 * Fetches the command queue and executes each command. It is possible that the
 * queue will not be empty after this function has completed since the executed
 * commands may have run callbacks which queued more commands.
 *
 * Returns the number of executed commands.
 */
- (int)executeQueuedCommands
{
    // Grab all the queued commands from the JS side.
    NSString* queuedCommandsJSON =
    [self.webView stringByEvaluatingJavaScriptFromString:
     @"PhoneGap.getAndClearQueuedCommands()"];
    
    // Parse the returned JSON array.
    //PG_SBJsonParser* jsonParser = [[[PG_SBJsonParser alloc] init] autorelease];
    NSArray* queuedCommands =
    [queuedCommandsJSON objectFromJSONString];
    
    // Iterate over and execute all of the commands.
    for (NSString* commandJson in queuedCommands) {
        [self execute:
         [InvokedUrlCommand commandFromObject:
          [commandJson mutableObjectFromJSONString]]];
    }
    
    return [queuedCommands count];
}


- (BOOL) execute:(InvokedUrlCommand*)command
{
    if (command.className == nil || command.methodName == nil) {
        return NO;
    }
    
    // Fetch an instance of this class
    PGPlugin* obj = nil; //TODO!!!! [self getCommandInstance:command.className];
    
    if (!([obj isKindOfClass:[PGPlugin class]])) { // still allow deprecated class, until 1.0 release
        NSLog(@"ERROR: Plugin '%@' not found, or is not a PGPlugin. Check your plugin mapping in PhoneGap.plist.", command.className);
        return NO;
    }
    BOOL retVal = YES;
    
    // construct the fill method name to ammend the second argument.
    NSString* fullMethodName = [[NSString alloc] initWithFormat:@"%@:withDict:", command.methodName];
    if ([obj respondsToSelector:NSSelectorFromString(fullMethodName)]) {
        [obj performSelector:NSSelectorFromString(fullMethodName) withObject:command.arguments withObject:command.options];
    } else {
        // There's no method to call, so throw an error.
        NSLog(@"ERROR: Method '%@' not defined in Plugin '%@'", fullMethodName, command.className);
        retVal = NO;
    }
    [fullMethodName release];
    
    return retVal;
}

#pragma mark - Misc

- (NSString*) pathForResource:(NSString*)resourcePath
{
    NSBundle * mainBundle = [NSBundle mainBundle];
    NSMutableArray *directoryParts = [NSMutableArray arrayWithArray:[resourcePath componentsSeparatedByString:@"/"]];
    NSString       *filename       = [directoryParts lastObject];
    [directoryParts removeLastObject];
    
    NSString* directoryPartsJoined =[directoryParts componentsJoinedByString:@"/"];
    NSString* directoryStr = self.wwwFolderName;
    
    if ([directoryPartsJoined length] > 0) {
        directoryStr = [NSString stringWithFormat:@"%@/%@", self.wwwFolderName, [directoryParts componentsJoinedByString:@"/"]];
    }
    
    return [mainBundle pathForResource:filename
                                ofType:@""
                           inDirectory:directoryStr];
}


@end
