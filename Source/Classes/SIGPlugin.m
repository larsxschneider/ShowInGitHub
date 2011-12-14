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
@property (nonatomic, assign) NSUInteger currentlySelectedLineNumber;

@end

// ------------------------------------------------------------------------------------------


@implementation SIGPlugin


@synthesize ideWorkspaceWindow = _ideWorkspaceWindow;
@synthesize currentlySelectedLineNumber = _currentlySelectedLineNumber;


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
    [super dealloc];
}


// ------------------------------------------------------------------------------------------
#pragma mark - Helper
// ------------------------------------------------------------------------------------------
- (NSURL *)activeDocument
{
    for (id workspaceWindowController in [IDEWorkspaceWindowControllerClass workspaceWindowControllers])
    {
        if ([workspaceWindowController workspaceWindow] == self.ideWorkspaceWindow)
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
        self.ideWorkspaceWindow = [notification object];
    }
}


- (void)sourceTextViewSelectionDidChange:(NSNotification *)notification
{
	id view = [notification object];
	if ([view isMemberOfClass:DVTSourceTextViewClass])
    {
        NSString *sourceTextUntilSelection = [[view string] substringWithRange:NSMakeRange(0, [view selectedRange].location)];
        self.currentlySelectedLineNumber = [[sourceTextUntilSelection componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] count];
	}
}


- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // Application did finish launching is only send once. We do not need it anymore.
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self
                  name:NSApplicationDidFinishLaunchingNotification
                object:NSApp];

    // Hook in the menu.
    NSMenu* toolsMenu = [[NSMenu allocWithZone:[NSMenu menuZone]] initWithTitle:@"6Tools"];
    NSMenuItem* toolsItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:@"6Tools" 
                                                                                 action:NULL 
                                                                          keyEquivalent:@""];
    toolsItem.enabled = YES;
    toolsItem.submenu = toolsMenu;
    
    NSMenuItem* openCommitItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:@"Show in GitHub" 
                                                                                      action:@selector(openCommitInGitHub:) 
                                                                               keyEquivalent:@""];
    openCommitItem.target = self;
    [toolsMenu addItem:openCommitItem];
    
    [[NSApp mainMenu] insertItem:toolsItem atIndex:7];
 
    [toolsMenu release];
    [toolsItem release];
}


// ------------------------------------------------------------------------------------------
#pragma mark - Open Commit in GitHub
// ------------------------------------------------------------------------------------------
// Performs a git command with given args in the given directory
- (NSString *)outputGitWithArguments:(NSArray *)args inPath:(NSString *)path
{
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


- (void)openCommitInGitHub:(id)sender
{
    NSUInteger lineNumber = self.currentlySelectedLineNumber;
    NSURL *activeDocumentURL = [self activeDocument];
    NSString *activeDocumentFullPath = [activeDocumentURL path];
    NSString *activeDocumentDirectoryPath = [[activeDocumentURL URLByDeletingLastPathComponent] path];

    
    // Get github username and repo name
    NSString *githubURLComponent;    
    NSArray *args = [NSArray arrayWithObjects:@"--no-pager", @"remote", @"-v", nil];
    NSArray *remotes = [[self outputGitWithArguments:args inPath:activeDocumentDirectoryPath] componentsSeparatedByString:@"\n"];
    NSLog(@"Remotes found: %@", remotes);
    
    for (NSString *remote in remotes)
    {
        NSRange begin = [remote rangeOfString:@"git@github.com:"];
        if (begin.location == NSNotFound) begin = [remote rangeOfString:@"https://github.com/"];
        NSRange end = [remote rangeOfString:@".git (fetch)"];
        
        if ((begin.location != NSNotFound) && (end.location != NSNotFound))
        {
            NSUInteger githubURLBegin = begin.location + begin.length;
            NSUInteger githubURLLength = end.location - githubURLBegin;
            githubURLComponent = [remote substringWithRange:NSMakeRange(githubURLBegin, githubURLLength)];
            break;
        }
    }
    
    if (githubURLComponent == nil)
    {
        NSRunAlertPanel(@"Error", @"Unable to find github remote URL.", @"OK", nil, nil);
        return;
    }
    
    
    // Get commit hash, original filename, original line
    args = [NSArray arrayWithObjects:@"--no-pager", @"blame",
                                     [NSString stringWithFormat:@"-L%d,%d", lineNumber, lineNumber],
                                     @"-l", @"-s", @"-n", @"-f", @"-p",
                                     activeDocumentFullPath,
                                     nil];
    NSString *rawLastCommitHash = [self outputGitWithArguments:args inPath:activeDocumentDirectoryPath];
    NSArray *commitHashInfo = [rawLastCommitHash componentsSeparatedByString:@" "];
    
    if (commitHashInfo.count < 2)
    {
        NSRunAlertPanel(@"Error", @"Unable to find filename with git blame.", @"OK", nil, nil);
        return;
    }
    
    NSString *commitHash = [commitHashInfo objectAtIndex:0];
    NSString *commitLine = [commitHashInfo objectAtIndex:1];
    
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
    NSLog(@"Commit files: %@", files);
    NSRange filePositionInCommit = [files rangeOfString:commitFilename];
    
    if (filePositionInCommit.location == NSNotFound)
    {
        NSRunAlertPanel(@"Error", @"Unable to find file in commit.", @"OK", nil, nil);
        return;
    }
    
    NSString *filesUntilFilename = [files substringToIndex:filePositionInCommit.location];
    NSUInteger fileNumber = [[filesUntilFilename componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] count] - 2;
    
    
    // Create GitHub URL and open browser
    NSString *commitURL = [NSString stringWithFormat:@"https://github.com/%@/commit/%@#L%dR%@",
                           githubURLComponent,
                           commitHash,
                           fileNumber,
                           commitLine];
    
    [NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:[NSArray arrayWithObjects:commitURL, nil]];
}


@end
