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
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        plugin = [[SIGPlugin alloc] init];
        [pool drain];
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
    [super dealloc];
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
            return [[[workspaceWindowController editorArea] primaryEditorDocument] fileURL];
        }
    }
    
    return nil;
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
        sixToolsMenuItem.submenu = [[[NSMenu allocWithZone:[NSMenu menuZone]] initWithTitle:sixToolsMenuItem.title] autorelease];
        [[NSApp mainMenu] insertItem:sixToolsMenuItem atIndex:7];
        [sixToolsMenuItem release];
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
    NSMenuItem* openCommitItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:@"Open commit on GitHub" 
                                                                                      action:@selector(openCommitOnGitHub:) 
                                                                               keyEquivalent:@""];
    openCommitItem.target = self;
    [sixToolsMenu addItem:openCommitItem];
    
    NSMenuItem* openFileItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:@"Open file on GitHub" 
                                                                                    action:@selector(openFileOnGitHub:) 
                                                                             keyEquivalent:@""];
    openFileItem.target = self;
    [sixToolsMenu addItem:openFileItem];
    
    [openCommitItem release];
    [openFileItem release];
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
    task.launchPath = @"/usr/bin/git";
    task.currentDirectoryPath = path;
    task.arguments = args;
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
    
    [task release];
    return [output autorelease];
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
    NSArray *args = [NSArray arrayWithObjects:@"--no-pager", @"remote", @"-v", nil];
    NSArray *remotes = [[self outputGitWithArguments:args inPath:dir] componentsSeparatedByString:@"\n"];
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
    
    return githubURLComponent;
}


- (BOOL)canOpenURL:(NSString *)urlString
{
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"HEAD";

    NSURLResponse *response;
    NSError *error;
    NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

    [request release];

    if (data && [response isKindOfClass:NSHTTPURLResponse.class])
    {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        return httpResponse.statusCode >= 200 && httpResponse.statusCode < 400;
    }

    return NO;
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
    
    if (githubRepoPath.length == 0)
    {
        NSRunAlertPanel(@"Error", @"Unable to find github remote URL.", @"OK", nil, nil);
        return;
    }
    
    // Get commit hash, original filename, original line
    NSArray *args = [NSArray arrayWithObjects:@"--no-pager", @"blame",
                                     [NSString stringWithFormat:@"-L%ld,%ld", (unsigned long)lineNumber, (unsigned long)lineNumber],
                                     @"-l", @"-s", @"-n", @"-f", @"-p",
                                     activeDocumentFullPath,
                                     nil];
    NSString *rawLastCommitHash = [self outputGitWithArguments:args inPath:activeDocumentDirectoryPath];
    NSLog(@"GIT blame: %@", rawLastCommitHash);
    NSArray *commitHashInfo = [rawLastCommitHash componentsSeparatedByString:@" "];
    
    if (commitHashInfo.count < 2)
    {
        NSRunAlertPanel(@"Error", @"Unable to find filename with git blame.", @"OK", nil, nil);
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
        NSRunAlertPanel(@"Error", @"Unable to find filename with git blame.", @"OK", nil, nil);
        return;
    }
    
    NSString *filenameRaw = [rawLastCommitHash substringFromIndex:filenamePositionInBlame.location + filenamePositionInBlame.length + 1];
    NSString *commitFilename = [[filenameRaw componentsSeparatedByString:@"\n"] objectAtIndex:0];
    NSLog(@"Commit hash found: %@ %@ %@ ", commitHash, commitFilename, commitLine);
    
    
    // Get position of the file in the commit
    args = [NSArray arrayWithObjects:@"--no-pager", @"show", @"--name-only", @"--pretty=format:", commitHash, nil];
    NSString *files = [self outputGitWithArguments:args inPath:activeDocumentDirectoryPath];
    NSLog(@"GIT show: %@", files);
    NSRange filePositionInCommit = [files rangeOfString:commitFilename];
    
    if (filePositionInCommit.location == NSNotFound)
    {
        NSRunAlertPanel(@"Error", @"Unable to find file in commit.", @"OK", nil, nil);
        return;
    }
    
    NSString *filesUntilFilename = [files substringToIndex:filePositionInCommit.location];
    NSUInteger fileNumber = [[filesUntilFilename componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] count] - 2;

    NSString *path = nil;

    if ( [self isGithubRepo:githubRepoPath] == YES ) {

        // Create GitHub URL and open browser
        path = [NSString stringWithFormat:@"/commit/%@#L%ldR%@",
                commitHash,
                (unsigned long)fileNumber,
                commitLine];

    } else if ( [self isBitBucketRepo:githubRepoPath] == YES ) {

        path = [NSString stringWithFormat:@"/commits/%@#L%ldR%@",
                commitHash,
                (unsigned long)fileNumber,
                commitLine];

    }

    if (path != nil) {

        [self openRepo:githubRepoPath withPath:path];
    }
}


- (void)openFileOnGitHub:(id)sender
{
    NSUInteger startLineNumber = self.selectionStartLineNumber;
    NSUInteger endLineNumber = self.selectionEndLineNumber;
    
    NSURL *activeDocumentURL = [self activeDocument];
    NSString *activeDocumentFilename = [activeDocumentURL lastPathComponent];
    NSString *activeDocumentFullPath = [activeDocumentURL path];
    NSString *activeDocumentDirectoryPath = [[activeDocumentURL URLByDeletingLastPathComponent] path];
    
    NSString *githubRepoPath = [self githubRepoPathForDirectory:activeDocumentDirectoryPath];
    
    if (githubRepoPath.length == 0)
    {
        NSRunAlertPanel(@"Error", @"Unable to find github remote URL.", @"OK", nil, nil);
        return;
    }
    
    // Get last commit hash
    NSArray *args = [NSArray arrayWithObjects:@"--no-pager", @"log", @"-n1", @"--no-decorate",
                     activeDocumentFullPath,
                     nil];
    NSString *rawLastCommitHash = [self outputGitWithArguments:args inPath:activeDocumentDirectoryPath];
    NSLog(@"GIT log: %@", rawLastCommitHash);
    NSArray *commitHashInfo = [rawLastCommitHash componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if (commitHashInfo.count < 2)
    {
        NSRunAlertPanel(@"Error", @"Unable to find filename with git log.", @"OK", nil, nil);
        return;
    }

    NSString *commitHash = [commitHashInfo objectAtIndex:1];
    
    // Get file with path in the commit
    args = [NSArray arrayWithObjects:@"--no-pager", @"show", @"--name-only", @"--pretty=format:", commitHash, nil];
    NSString *files = [self outputGitWithArguments:args inPath:activeDocumentDirectoryPath];
    NSLog(@"GIT show: %@", files);
    
    NSString *filenameWithPathInCommit = nil;
    for (NSString *filenameWithPath in [files componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
    {
        if ([filenameWithPath hasSuffix:activeDocumentFilename])
        {
            filenameWithPathInCommit = filenameWithPath;
            break;
        }
    }
    
    if (filenameWithPathInCommit == nil)
    {
        NSRunAlertPanel(@"Error", @"Unable to find file in commit.", @"OK", nil, nil);
        return;
    }

    NSString *path = nil;

    if ( [self isGithubRepo:githubRepoPath] == YES ) {

        // Create GitHub URL and open browser
        path = [NSString stringWithFormat:@"/blob/%@/%@#L%ld-%ld",
                commitHash,
                [filenameWithPathInCommit stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding],
                (unsigned long)startLineNumber,
                (unsigned long)endLineNumber];

    } else if ( [self isBitBucketRepo:githubRepoPath] == YES ) {

        path = [NSString stringWithFormat:@"/src/%@/%@#L%ld-%ld",
                commitHash,
                [filenameWithPathInCommit stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding],
                (unsigned long)startLineNumber,
                (unsigned long)endLineNumber];

    }

    if (path != nil) {

        [self openRepo:githubRepoPath withPath:path];
    }
  
}

- (BOOL) isGithubRepo:(NSString *)repo
{
    NSArray *servers = @[@"github.com", @"github.org"];

    for (NSString *s in servers) {

        NSRange r = [[repo lowercaseString] rangeOfString:s];

        if (r.location != NSNotFound) {

            return YES;
        }
    }

    return NO;
}

- (BOOL) isBitBucketRepo:(NSString *)repo
{
    NSArray *servers = @[@"bitbucket.com", @"bitbucket.org"];

    for (NSString *s in servers) {

        NSRange r = [[repo lowercaseString] rangeOfString:s];

        if (r.location != NSNotFound) {

            return YES;
        }
    }

    return NO;
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

    [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:[NSArray arrayWithObjects:url, nil]];
}

@end
