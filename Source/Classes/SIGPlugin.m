/*
 *  Copyright (c) 2011, Lars Schneider
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are met:
 *
 *  Redistributions of source code must retain the above copyright notice, this
 *  list of conditions and the following disclaimer.
 *  Redistributions in binary form must reproduce the above copyright notice,
 *  this list of conditions and the following disclaimer in the documentation
 *  and/or other materials provided with the distribution.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 *  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 *  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 *  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 *  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 *  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 *  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 *  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 *  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 *  POSSIBILITY OF SUCH DAMAGE.
 *
 */

#import "SIGPlugin.h"

#import <IDEKit/IDEWorkspaceWindowController.h>
#import <IDEKit/IDEEditorArea.h>
#import <CommonCrypto/CommonDigest.h>

id objc_getClass(const char* name);

static Class DVTSourceTextViewClass;
static Class IDESourceCodeEditorClass;
static Class IDEApplicationClass;
static Class IDEWorkspaceWindowControllerClass;


// ------------------------------------------------------------------------------------------

@interface SIGPlugin()

@property (nonatomic, strong) id ideWorkspaceWindow;
@property (nonatomic, assign) NSUInteger selectionStartLineNumber;
@property (nonatomic, assign) NSUInteger selectionEndLineNumber;
@property (nonatomic, assign) BOOL useHTTPS;

@end

// ------------------------------------------------------------------------------------------


@implementation SIGPlugin


@synthesize ideWorkspaceWindow = _ideWorkspaceWindow;
@synthesize selectionStartLineNumber = _selectionStartLineNumber;
@synthesize selectionEndLineNumber = _selectionEndLineNumber;


+ (void)pluginDidLoad:(NSBundle *)bundle
{
    DVTSourceTextViewClass = objc_getClass("DVTSourceTextView");
    IDESourceCodeEditorClass = objc_getClass("IDESourceCodeEditor");
    IDEApplicationClass = objc_getClass("IDEApplication");
    IDEWorkspaceWindowControllerClass = objc_getClass("IDEWorkspaceWindowController");
    
    static dispatch_once_t pred;
    static SIGPlugin *plugin = nil;
    
    dispatch_once(&pred, ^{
        plugin = [[SIGPlugin alloc] init];
    });
}


- (id)init
{
    if ((self = [super init]))
    {
        // Listen to application did finish launching notification to hook in the menu.
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        
        [nc addObserver:self
               selector:@selector(applicationDidFinishLaunching:)
                   name:NSApplicationDidFinishLaunchingNotification
                 object:NSApp];
        
        [nc addObserver:self
               selector:@selector(sourceTextViewSelectionDidChange:)
                   name:NSTextViewDidChangeSelectionNotification
                 object:nil];
        
        [nc addObserver:self
               selector:@selector(fetchActiveIDEWorkspaceWindow:)
                   name:NSWindowDidUpdateNotification
                 object:nil];
    }
    
    return self;
}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


// ------------------------------------------------------------------------------------------
#pragma mark - Helper
// ------------------------------------------------------------------------------------------
- (NSURL *)activeDocument
{
    NSArray *windows = [IDEWorkspaceWindowControllerClass workspaceWindowControllers];
    for (id workspaceWindowController in windows)
    {
        if ([workspaceWindowController workspaceWindow] == self.ideWorkspaceWindow || windows.count == 1)
        {
            id document = [[workspaceWindowController editorArea] primaryEditorDocument];
            return [document fileURL];
        }
    }
    
    return nil;
}


+ (NSString *)md5HexDigest:(NSString *)input
{
    const char* str = [input UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), result);

    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for(int i = 0; i<CC_MD5_DIGEST_LENGTH; i++)
    {
        [ret appendFormat:@"%02x", result[i]];
    }
    return ret;
}


- (void)createErrorReportForGitArgs:(NSArray *)gitArgs withOutput:(NSString *)gitOutput
{
    NSString *gitVersion = [self outputGitWithArguments:@[@"--version"] inPath:@"~"];
    NSString *body = [NSString stringWithFormat:
        @"!!! ATTENTION: Please redact any private information below !!!\n\n"
         "Call:\ngit %@\n\nOutput:\n%@\n\nVersion:\n%@",
         [gitArgs componentsJoinedByString:@" "], gitOutput, gitVersion];
    NSString *mailString = [NSString stringWithFormat:
        @"mailto:?to=larsxschneider+showingithub@gmail.com&subject=ShowInGithub-Error-Report&body=%@",
        [body stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:mailString]];
}


- (void)showGitError:(NSString *)message gitArgs:(NSArray *)gitArgs output:(NSString *)gitOutput
{
    if (NSRunAlertPanel(@"Git Error", message, @"OK", @"Create error report", nil) == 0)
    {
        [self createErrorReportForGitArgs:gitArgs withOutput:gitOutput];
    }
}


// ------------------------------------------------------------------------------------------
#pragma mark - Notifications
// ------------------------------------------------------------------------------------------
- (void)fetchActiveIDEWorkspaceWindow:(NSNotification *)notification
{
    id window = [notification object];
    if ([window isKindOfClass:[NSWindow class]] && [window isMainWindow])
    {
        self.ideWorkspaceWindow = window;
    }
}


- (void)sourceTextViewSelectionDidChange:(NSNotification *)notification
{
	id view = [notification object];
	if ([view isMemberOfClass:DVTSourceTextViewClass])
    {
        NSString *sourceTextUntilSelection = [[view string] substringWithRange:NSMakeRange(0, [view selectedRange].location)];
        self.selectionStartLineNumber = [[sourceTextUntilSelection componentsSeparatedByCharactersInSet:
                                            [NSCharacterSet newlineCharacterSet]] count];
        
        NSString *sourceTextSelection = [[view string] substringWithRange:[view selectedRange]];
        NSUInteger selectedLines = [[sourceTextSelection componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] count];
        self.selectionEndLineNumber = self.selectionStartLineNumber + (selectedLines > 1 ? selectedLines - 2 : 0);
    }
}


- (NSMenu *)sixToolsMenu
{
    // Search if the 6Tools menu is already present in Xcode
    NSMenuItem *sixToolsMenuItem = nil;
    for (NSMenuItem *menuItem in [[NSApp mainMenu] itemArray])
    {
        if ([menuItem.title isEqualToString:@"GitHub"])
        {
            sixToolsMenuItem = menuItem;
            break;
        }
    }
    
    // 6Tools menu was not found, create one.
    if (sixToolsMenuItem == nil)
    {
        sixToolsMenuItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:@"GitHub" 
                                                                                action:NULL 
                                                                         keyEquivalent:@""];
        
        sixToolsMenuItem.enabled = YES;
        sixToolsMenuItem.submenu = [[NSMenu allocWithZone:[NSMenu menuZone]] initWithTitle:sixToolsMenuItem.title];
        [[NSApp mainMenu] insertItem:sixToolsMenuItem atIndex:7];
    }
    
    return sixToolsMenuItem.submenu;
}


- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // Application did finish launching is only send once. We do not need it anymore.
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self
                  name:NSApplicationDidFinishLaunchingNotification
                object:NSApp];

    
    NSMenu *sixToolsMenu = [self sixToolsMenu];

    // Create action menu items
    NSMenuItem *openCommitItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:@"Open commit on GitHub"
                                                                                      action:@selector(openCommitOnGitHub:) 
                                                                               keyEquivalent:@"c"];
    [openCommitItem setKeyEquivalentModifierMask:NSControlKeyMask];

    openCommitItem.target = self;
    [sixToolsMenu addItem:openCommitItem];
    
    NSMenuItem *openFileItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:@"Open file on GitHub"
                                                                                    action:@selector(openFileOnGitHub:) 
                                                                             keyEquivalent:@"g"];
    [openFileItem setKeyEquivalentModifierMask:NSControlKeyMask];
    
    openFileItem.target = self;
    [sixToolsMenu addItem:openFileItem];
}


// ------------------------------------------------------------------------------------------
#pragma mark - Open Commit in GitHub
// ------------------------------------------------------------------------------------------
// Performs a git command with given args in the given directory
- (NSString *)outputGitWithArguments:(NSArray *)args inPath:(NSString *)path
{
    if (path.length == 0)
    {
        NSLog(@"Invalid path for git working directory.");
        return nil;
    }
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/xcrun";
    task.currentDirectoryPath = path;
    task.arguments = [@[@"git", @"--no-pager"] arrayByAddingObjectsFromArray:args];
    task.standardOutput = [NSPipe pipe];
    NSFileHandle *file = [task.standardOutput fileHandleForReading];
    
    [task launch];

    // For some reason [task waitUntilExit]; does not return sometimes. Therefore this rather hackish solution:
    int count = 0;
    while (task.isRunning && (count < 10))
    {
        [NSThread sleepForTimeInterval:0.1];
        count++;
    }
 
    NSString *output = [[NSString alloc] initWithData:[file readDataToEndOfFile] encoding:NSUTF8StringEncoding];

    return output;
}


- (NSString *)githubRepoPathForDirectory:(NSString *)dir
{
    if (dir.length == 0)
    {
        NSLog(@"Invalid git repository path.");
        return nil;
    }

    // Get github username and repo name
    NSString *githubURLComponent = nil;
    NSArray *args = @[@"remote", @"--verbose"];
    NSString *output = [self outputGitWithArguments:args inPath:dir];
    NSArray *remotes = [output componentsSeparatedByString:@"\n"];
    NSLog(@"GIT remotes: %@", remotes);

    NSMutableSet *remotePaths = [NSMutableSet setWithCapacity:1];
    
    for (NSString *remote in remotes)
    {       
        // Check for SSH protocol
        NSRange begin = [remote rangeOfString:@"git@"];

        if (begin.location == NSNotFound)
        {
            // SSH protocol not found, check for GIT protocol
            begin = [remote rangeOfString:@"git://"];
        }
        if (begin.location == NSNotFound)
        {
            // HTTPS protocol check
            begin = [remote rangeOfString:@"https://"];
        }
        if (begin.location == NSNotFound)
        {
            // HTTP protocol check
            begin = [remote rangeOfString:@"http://"];
        }

        NSRange end = [remote rangeOfString:@".git (fetch)"];

        if (end.location == NSNotFound)
        {
            // Alternate remote url end
            end = [remote rangeOfString:@" (fetch)"];
        }

        if ((begin.location != NSNotFound) &&
            (end.location != NSNotFound))
        {
            NSUInteger githubURLBegin = begin.location + begin.length;
            NSUInteger githubURLLength = end.location - githubURLBegin;
            githubURLComponent = [[remote
                                   substringWithRange:NSMakeRange(githubURLBegin, githubURLLength)]
                                    stringByReplacingOccurrencesOfString:@":" withString:@"/"];

            [remotePaths addObject:githubURLComponent];
        }
    }

    if (remotePaths.count > 1)
    {
        NSArray *sortedRemotePaths = remotePaths.allObjects;

        // Ask the user what remote to use.
        // Attention: Due to NSRunAlertPanel maximal three remotes are supported.
        NSInteger result = NSRunAlertPanel(@"Question",
                        [NSString stringWithFormat:@"This repository has %li remotes configured. Which one do you want to open?", remotePaths.count],
                        [sortedRemotePaths objectAtIndex:0],
                        [sortedRemotePaths objectAtIndex:1],
                        (sortedRemotePaths.count > 2 ? [sortedRemotePaths objectAtIndex:2] : nil));

        if (result == 1) githubURLComponent = [sortedRemotePaths objectAtIndex:0];
        else if (result == 0) githubURLComponent = [sortedRemotePaths objectAtIndex:1];
        else if (sortedRemotePaths.count > 2) githubURLComponent = [sortedRemotePaths objectAtIndex:2];
    }
    
    if (githubURLComponent.length == 0)
    {
        [self showGitError:@"Unable to find github remote URL." gitArgs:args output:output];
        return nil;
    }
    
    return githubURLComponent;
}


- (BOOL)canOpenURL:(NSString *)urlString
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"HEAD";

    NSURLResponse *response;
    NSError *error;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

    if (data && [response isKindOfClass:NSHTTPURLResponse.class])
    {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        return httpResponse.statusCode >= 200 && httpResponse.statusCode < 400;
    }

    return NO;
}


- (BOOL)isBitBucketRepo:(NSString *)repo
{
    NSArray *servers = @[@"bitbucket.com", @"bitbucket.org"];
    for (NSString *server in servers)
    {
        NSRange rangeOfRepo = [[repo lowercaseString] rangeOfString:server];
        if (rangeOfRepo.location != NSNotFound)
        {
            return YES;
        }
    }

    return NO;
}


- (NSString *)filenameWithPathInCommit:(NSString *)commitHash forActiveDocumentURL:(NSURL *)activeDocumentURL
{
    NSArray *args = @[@"show", @"--name-only", @"--pretty=format:", commitHash];
    NSString *activeDocumentDirectoryPath = [[activeDocumentURL URLByDeletingLastPathComponent] path];
    NSString *files = [self outputGitWithArguments:args inPath:activeDocumentDirectoryPath];
    NSLog(@"GIT show: %@", files);

    NSString *activeDocumentFilename = [activeDocumentURL lastPathComponent];
    NSString *filenameWithPathInCommit = nil;
    for (NSString *filenameWithPath in [files componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
    {
        if ([filenameWithPath hasSuffix:activeDocumentFilename])
        {
            filenameWithPathInCommit = [filenameWithPath stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding];
            break;
        }
    }

    if (!filenameWithPathInCommit)
    {
        [self showGitError:@"Unable to find file in commit." gitArgs:args output:files];
        return nil;
    }

    return filenameWithPathInCommit;
}


- (void)openCommitOnGitHub:(id)sender
{
    NSUInteger lineNumber = self.selectionStartLineNumber;
    NSURL *activeDocumentURL = [self activeDocument];

    if (!activeDocumentURL)
    {
        NSRunAlertPanel(@"Error", @"Unable to find Xcode document. Xcode version compatible to ShowInGithub?", @"OK", nil, nil);
        return;
    }

    NSString *activeDocumentFullPath = [activeDocumentURL path];
    NSString *activeDocumentDirectoryPath = [[activeDocumentURL URLByDeletingLastPathComponent] path];

    NSString *githubRepoPath = [self githubRepoPathForDirectory:activeDocumentDirectoryPath];
    
    if (!githubRepoPath)
    {
        return;
    }
    
    // Get commit hash, original filename, original line
    NSArray *args = @[
            @"blame", [NSString stringWithFormat:@"-L%ld,%ld", (unsigned long)lineNumber, (unsigned long)lineNumber],
            @"-l", @"-s", @"--show-number", @"--show-name", @"--porcelain", activeDocumentFullPath];
    NSString *rawLastCommitHash = [self outputGitWithArguments:args inPath:activeDocumentDirectoryPath];
    NSLog(@"GIT blame: %@", rawLastCommitHash);
    NSArray *commitHashInfo = [rawLastCommitHash componentsSeparatedByString:@" "];
    
    if (commitHashInfo.count < 2)
    {
        [self showGitError:@"Unable to find commit hash with git blame." gitArgs:args output:rawLastCommitHash];
        return;
    }
    
    NSString *commitHash = [commitHashInfo objectAtIndex:0];
    NSString *commitLine = [commitHashInfo objectAtIndex:1];
    
    if ([commitHash isEqualToString:@"0000000000000000000000000000000000000000"])
    {
        NSRunAlertPanel(@"Error", @"Line not yet commited.", @"OK", nil, nil);
        return;
    }
    
    NSRange filenamePositionInBlame = [rawLastCommitHash rangeOfString:@"\nfilename"];
    if (filenamePositionInBlame.location == NSNotFound)
    {
        [self showGitError:@"Unable to find filename with git blame." gitArgs:args output:rawLastCommitHash];
        return;
    }
    
    NSString *filenameRaw = [rawLastCommitHash substringFromIndex:filenamePositionInBlame.location + filenamePositionInBlame.length + 1];
    NSString *commitFilename = [[filenameRaw componentsSeparatedByString:@"\n"] objectAtIndex:0];
    NSLog(@"Commit hash found: %@ %@ %@ ", commitHash, commitFilename, commitLine);

    NSString *filenameWithPathInCommit = [self filenameWithPathInCommit:commitHash forActiveDocumentURL:activeDocumentURL];
    if (!filenameWithPathInCommit)
    {
        return;
    }

    NSString *path = nil;
    if ([self isBitBucketRepo:githubRepoPath])
    {
        path = [NSString stringWithFormat:@"/commits/%@#L%@T%@",
                commitHash,
                filenameWithPathInCommit,
                commitLine];
    }
    else
    {
        // If the repo path does not include a bitbucket server, we assume a github server. Consequently we can
        // support GitHub enterprise instances with arbitrary server names.
        path = [NSString stringWithFormat:@"/commit/%@#diff-%@R%@",
                commitHash,
                [self.class md5HexDigest:filenameWithPathInCommit],
                commitLine];
    }

    [self openRepo:githubRepoPath withPath:path];
}


- (void)openFileOnGitHub:(id)sender
{
    NSUInteger startLineNumber = self.selectionStartLineNumber;
    NSUInteger endLineNumber = self.selectionEndLineNumber;
    
    NSURL *activeDocumentURL = [self activeDocument];
    NSString *activeDocumentFullPath = [activeDocumentURL path];
    NSString *activeDocumentDirectoryPath = [[activeDocumentURL URLByDeletingLastPathComponent] path];
    
    NSString *githubRepoPath = [self githubRepoPathForDirectory:activeDocumentDirectoryPath];
    
    if (!githubRepoPath)
    {
        return;
    }
    
    // Get last commit hash
    NSArray *args = @[@"log", @"-n1", @"--no-decorate", activeDocumentFullPath];
    NSString *rawLastCommitHash = [self outputGitWithArguments:args inPath:activeDocumentDirectoryPath];
    NSLog(@"GIT log: %@", rawLastCommitHash);
    NSArray *commitHashInfo = [rawLastCommitHash componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if (commitHashInfo.count < 2)
    {
        [self showGitError:@"U2nable to find filename with git log." gitArgs:args output:rawLastCommitHash];
        return;
    }

    NSString *commitHash = [commitHashInfo objectAtIndex:1];
    NSString *filenameWithPathInCommit = [self filenameWithPathInCommit:commitHash forActiveDocumentURL:activeDocumentURL];

    if (!filenameWithPathInCommit)
    {
        return;
    }

    NSString *path = nil;

    if ([self isBitBucketRepo:githubRepoPath])
    {
        path = [NSString stringWithFormat:@"/src/%@/%@#cl-%ld",
                commitHash,
                filenameWithPathInCommit,
                (unsigned long)startLineNumber];
    }
    else
    {
        // If the repo path does not include a bitbucket server, we assume a github server. Consequently we can
        // support GitHub enterprise instances with arbitrary server names.
        path = [NSString stringWithFormat:@"/blob/%@/%@#L%ld-%ld",
                commitHash,
                filenameWithPathInCommit,
                (unsigned long)startLineNumber,
                (unsigned long)endLineNumber];

    }

    [self openRepo:githubRepoPath withPath:path];
}


- (void)openRepo:(NSString *)repo withPath:(NSString *)path
{
    NSString *secureBaseUrl = [NSString stringWithFormat:@"https://%@", repo];

    // Check if HTTPS is available. Default to HTTPS without checking again if it is available at least once.
    if (!self.useHTTPS)
    {
        if ([self canOpenURL:secureBaseUrl])
        {
            self.useHTTPS = YES;
        }
    }

    NSString *url = [NSString stringWithFormat:@"%@%@", secureBaseUrl, path];
    if (!self.useHTTPS)
    {
        url = [NSString stringWithFormat:@"http://%@%@", repo, path];
    }

    [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[url]];
}


@end
