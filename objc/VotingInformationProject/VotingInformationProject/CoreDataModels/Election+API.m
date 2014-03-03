//
//  Election+API.m
//  VotingInformationProject
//
//  Created by Andrew Fink on 1/31/14.
//  
//

#import "Election+API.h"

@implementation Election (API)

// Error domain for this class for use in NSError
NSString * const VIPErrorDomain = @"com.votinginfoproject.whitelabel.error";

// Error codes used by this class and elsewhere in NSError
NSUInteger const VIPNoValidElections = 100;
NSUInteger const VIPInvalidUserAddress = 101;
NSUInteger const VIPAddressUnparseable = 102;
NSUInteger const VIPNoAddress = 103;
NSUInteger const VIPElectionUnknown = 104;
NSUInteger const VIPElectionOver = 105;
NSUInteger const VIPGenericAPIError = 200;

// String descriptions of the above error codes
// Get value with localizedDescriptionForErrorCode:
static NSString * VIPAddressUnparseableDescription;
static NSString * VIPNoAddressDescription;
static NSString * VIPGenericAPIErrorDescription;
static NSString * VIPElectionOverDescription;
static NSString * VIPElectionUnknownDescription;
static NSString * VIPInvalidUserAddressDescription;
static NSString * VIPNoValidElectionsDescription;


// Definitions for the various possible responses from the voterInfo API
// Not translated because these are used internally and are explicit maps to the
//  voterInfo query v1 response
NSString * const APIResponseSuccess = @"success";
NSString * const APIResponseElectionOver = @"electionOver";
NSString * const APIResponseElectionUnknown = @"electionUnknown";
NSString * const APIResponseNoStreetSegmentFound = @"noStreetSegmentFound";
NSString * const APIResponseMultipleStreetSegmentsFound = @"multipleStreetSegmentsFound";
NSString * const APIResponseNoAddressParameter = @"noAddressParameter";

+ (void) initialize
{
    [super initialize];

    // We define strings this way, rather than via extern NSString* const because localized strings
    // defined like so:
    //  NSString * const foo = @"foo";
    //  NSString *localizedFoo = NSLocalizedString(foo, nil);
    // is not picked up by the genstrings tool.
    VIPAddressUnparseableDescription = NSLocalizedString(@"Address unparseable. Please reformat your address or provide more detail such as street name.", nil);
    VIPNoAddressDescription = NSLocalizedString(@"No address provided", nil);
    VIPGenericAPIErrorDescription = NSLocalizedString(@"An unknown API error has occurred. Please try again later.", nil);
    VIPElectionOverDescription = NSLocalizedString(@"This election is over.", nil);
    VIPElectionUnknownDescription = NSLocalizedString(@"Unknown election. Please try again later.", nil);
    VIPInvalidUserAddressDescription = NSLocalizedString(@"Weird. It looks like we can't find your address. Maybe double check that it's right and try again.", nil);
    VIPNoValidElectionsDescription = NSLocalizedString(@"Sorry, there is no information for an upcoming election near you. Information about elections is generally available two to four weeks before the election date.", nil);
}


+ (Election*) getUnique:(NSString*)electionId
        withUserAddress:(UserAddress*)userAddress
{
    Election *election = nil;
    if (electionId && [electionId length] > 0 && [userAddress hasAddress]) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"electionId == %@ && userAddress == %@", electionId, userAddress];
        election = [Election MR_findFirstWithPredicate:predicate];
        if (!election) {
            election = [Election MR_createEntity];
            election.electionId = electionId;
            election.userAddress = userAddress;
#if DEBUG
            NSLog(@"Created new election with id: %@", electionId);
#endif
        } else {
#if DEBUG
            NSLog(@"Retrieved election %@ from data store", electionId);
#endif
        }
    }
    return election;
}

+ (NSString *)localizedDescriptionForErrorCode:(NSUInteger)errorCode
{
    switch (errorCode) {
        case VIPAddressUnparseable:
            return VIPAddressUnparseableDescription;

        case VIPNoAddress:
            return VIPNoAddressDescription;

        case VIPElectionOver:
            return VIPElectionOverDescription;

        case VIPElectionUnknown:
            return VIPElectionUnknownDescription;

        case VIPInvalidUserAddress:
            return VIPInvalidUserAddressDescription;

        case VIPNoValidElections:
            return VIPNoValidElectionsDescription;

        default:
            return VIPGenericAPIErrorDescription;
    }
}

+ (void) getElectionsAt:(UserAddress*)userAddress
           resultsBlock:(void (^)(NSArray * elections, NSError * error))resultsBlock
{
    if (![userAddress hasAddress]) {
        NSError *error = [NSError errorWithDomain:VIPErrorDomain
                                             code:VIPInvalidUserAddress
                                         userInfo:@{NSLocalizedDescriptionKey: VIPInvalidUserAddressDescription}];
        resultsBlock(@[], error);
        return;
    }

    // TODO: Attempt to get stored elections from the cache and display those rather than
    //          making a network request

    NSString *settingsPath = [[NSBundle mainBundle] pathForResource:@"settings" ofType:@"plist"];
    NSDictionary *appSettings = [[NSDictionary alloc] initWithContentsOfFile:settingsPath];
    BOOL appDebug = [[appSettings valueForKey:@"DEBUG"] boolValue];
    // Setup request manager
    // TODO: Refactor into separate class if multiple requests are made
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    manager.responseSerializer = [AFJSONResponseSerializer serializer];
    manager.responseSerializer.acceptableContentTypes = [manager.responseSerializer.acceptableContentTypes
                                                         setByAddingObjectsFromSet:[NSSet setWithObject:@"text/plain"]];

    NSString *requestUrl = [appSettings objectForKey:@"ElectionListURL"];
    NSLog(@"URL: %@", requestUrl);
    NSDictionary *requestParams = nil;

    [manager GET:requestUrl
      parameters:requestParams
         success:^(AFHTTPRequestOperation *operation, NSDictionary *responseObject) {
             
             // On Success
             NSArray *electionData = [responseObject objectForKey:@"elections"];
             if (!electionData) {
                 // table view will simply be empty
                 NSError *error = [NSError errorWithDomain:VIPErrorDomain
                                                      code:VIPNoValidElections
                                                  userInfo:@{NSLocalizedDescriptionKey: VIPNoValidElectionsDescription}];
                 resultsBlock(@[], error);
                 return;
             }

             // Init elections array
             NSUInteger numberOfElections = [electionData count];
             NSMutableArray *elections = [[NSMutableArray alloc] initWithCapacity:numberOfElections];

             // Loop elections and add valid ones to elections array
             for (NSDictionary *entry in electionData) {
                 // skip election if in the past and debug is disabled
                 if (!appDebug && ![Election isElectionDictValid:entry]) {
                     continue;
                 }

                 NSString *electionId = entry[@"id"];
                 Election *election = [Election getUnique:electionId
                                          withUserAddress:userAddress];
                 election.electionName = entry[@"name"];
                 [election setDateFromString:entry[@"electionDay"]];
                 [elections addObject:election];
             }

             // sort elections by date ascending now that theyre all in the future
             NSSortDescriptor *dateDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"date"
                                                                              ascending:YES];
             NSArray *sortDescriptors = [NSArray arrayWithObject:dateDescriptor];
             NSArray *sortedElections = [elections sortedArrayUsingDescriptors:sortDescriptors];

             NSManagedObjectContext *moc = [NSManagedObjectContext MR_contextForCurrentThread];
             [moc MR_saveToPersistentStoreWithCompletion:^(BOOL success, NSError *error) {
                 resultsBlock(sortedElections, error);
             }];

         } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
             resultsBlock(@[], error);
         }];

}

+ (BOOL) isElectionDictValid:(NSDictionary*)election {
    if (!election[@"id"]) {
        return NO;
    }
    if (!election[@"name"]) {
        return NO;
    }
    // setup date formatter
    NSDateFormatter *yyyymmddFormatter = [[NSDateFormatter alloc] init];
    [yyyymmddFormatter setDateFormat:@"yyyy-mm-dd"];
    NSDate *electionDate = [yyyymmddFormatter dateFromString:election[@"electionDay"]];
    if ([electionDate compare:[NSDate date]] != NSOrderedDescending) {
        return NO;
    }
    return YES;
}

- (NSString *) getDateString
{
    NSString *electionDateString = nil;
    if (self.date) {
        NSDateFormatter *yyyymmddFormatter = [[NSDateFormatter alloc] init];
        [yyyymmddFormatter setDateFormat:@"yyyy-mm-dd"];
        electionDateString = [yyyymmddFormatter stringFromDate:self.date];
    }
    return electionDateString;
}

- (void) setDateFromString:(NSString *)stringDate
{
    NSDateFormatter *yyyymmddFormatter = [[NSDateFormatter alloc] init];
    [yyyymmddFormatter setDateFormat:@"yyyy-mm-dd"];
    self.date = [yyyymmddFormatter dateFromString:stringDate];
}

- (NSArray*)filterPollingLocations:(VIPPollingLocationType)type
{
    NSArray *locations = [self getSorted:@"pollingLocations"
                              byProperty:@"isEarlyVoteSite"
                               ascending:NO];
    NSArray *filteredLocations = locations;
    if (type == VIPPollingLocationTypeEarlyVote) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"isEarlyVoteSite == YES"];
        filteredLocations = [locations filteredArrayUsingPredicate:predicate];
    } else if (type == VIPPollingLocationTypeNormal) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"isEarlyVoteSite == NO"];
        filteredLocations = [locations filteredArrayUsingPredicate:predicate];

    }
    return filteredLocations;
}

// For now always yes to test delete/update on CoreData
- (BOOL) shouldUpdate
{
    // Update if no last updated date
    if (!self.lastUpdated) {
        return YES;
    }
    // Update if all of these are empty
    if (!(self.pollingLocations || self.contests || self.states)) {
        return YES;
    }
    // Update if election data is more than x days old
    int days = 7;
    double secondsSinceUpdate = [self.lastUpdated timeIntervalSinceNow];
    if (secondsSinceUpdate < -1 * 60 * 60 * 24 * days) {
        return YES;
    }

    return NO;
}

- (void) getVoterInfoIfExpired:(void (^) (BOOL success, NSError *error)) statusBlock
{
    if ([self shouldUpdate]) {
        [self getVoterInfo:statusBlock];
    } else {
        statusBlock(YES, nil);
    }
}

/*
 A set of parsed data is unique on (electionId, UserAddress).
*/
- (void) getVoterInfo:(void (^) (BOOL success, NSError *error)) statusBlock
{
    if (![self.userAddress hasAddress]) {
        NSError *error = [NSError errorWithDomain:VIPErrorDomain
                                             code:VIPInvalidUserAddress
                                         userInfo:@{NSLocalizedDescriptionKey: VIPInvalidUserAddressDescription}];
        statusBlock(NO, error);
    }
    NSString *settingsPath = [[NSBundle mainBundle] pathForResource:@"CivicAPIKey" ofType:@"plist"];
    NSDictionary *settings = [[NSDictionary alloc] initWithContentsOfFile:settingsPath];

    NSString *appSettingsPath = [[NSBundle mainBundle] pathForResource:@"settings" ofType:@"plist"];
    NSDictionary *appSettings = [[NSDictionary alloc] initWithContentsOfFile:appSettingsPath];

    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    // Serializes the http body POST parameters as JSON, which is what the Civic Info API expects
    manager.requestSerializer = [AFJSONRequestSerializer serializer];
    manager.responseSerializer = [AFJSONResponseSerializer serializer];
    NSString *apiKey = [settings objectForKey:@"GoogleCivicInfoAPIKey"];
    NSDictionary *params = @{ @"address": self.userAddress.address };

    NSString *urlFormat = @"https://www.googleapis.com/civicinfo/us_v1/voterinfo/%@/lookup?key=%@&officialOnly=True";

    // Add query params to the url since AFNetworking serializes these internally anyway
    //  and the parameters parameter below attaches only to the http body for POST
    // Always use officialOnly = True
    if ([appSettings valueForKey:@"DEBUG"]) {
        urlFormat = @"https://www.googleapis.com/civicinfo/us_v1/voterinfo/%@/lookup?key=%@&officialOnly=True&productionDataOnly=false";
    }
    NSString *url =[NSString stringWithFormat:urlFormat, self.electionId, apiKey];
    NSLog(@"VoterInfo Query: %@", url);
    [manager POST:url
       parameters:params
          success:^(AFHTTPRequestOperation *operation, NSDictionary *json) {
              NSError *error = [self parseVoterInfoJSON:json];
              BOOL success = error ? NO : YES;
              statusBlock(success, error);
          }
          failure:^(AFHTTPRequestOperation *operation, NSError *error) {
              statusBlock(NO, error);
          }];
}

/*
 A set of parsed data is unique on (electionId, UserAddress).
*/
- (NSError*) parseVoterInfoJSON:(NSDictionary*)json
{
    NSError *error =[Election parseVoterInfoResponseStatus:json[@"status"]];
    if (error) {
        return error;
    }

    // First delete all old data
    [self deleteAllData];

    // Create the massive structure
    [self setFromDictionary:json];

    // Save ALL THE CHANGES
    NSManagedObjectContext *moc = [NSManagedObjectContext MR_contextForCurrentThread];
    [moc MR_saveToPersistentStoreWithCompletion:^(BOOL success, NSError *error) {
        NSLog(@"parseVoterInfoJSON saved: %d", success);
    }];
    return error;
}

- (void) setFromDictionary:(NSDictionary*)attributes
{
    // Parse Polling Locations
    NSArray *pollingLocations = attributes[@"pollingLocations"];
    for (NSDictionary *pollingLocation in pollingLocations) {
        PollingLocation *pl = [PollingLocation setFromDictionary:pollingLocation
                                               asEarlyVotingSite:NO];
        [self addPollingLocationsObject:pl];
    }

    // Parse polling locations
    NSArray *earlyVoteSites = attributes[@"earlyVoteSites"];
    for (NSDictionary *earlyVoteSite in earlyVoteSites) {
        PollingLocation *evs = [PollingLocation setFromDictionary:earlyVoteSite
                                                asEarlyVotingSite:YES];
        [self addPollingLocationsObject:evs];
    }

    // Parse States
    NSArray *states = attributes[@"state"];
    for (NSDictionary *state in states){
        [self addStatesObject:[State setFromDictionary:state]];
    }

    // Parse Contests
    NSArray *contests = attributes[@"contests"];
    for (NSDictionary *contest in contests){
        [self addContestsObject:[Contest setFromDictionary:contest]];
    }

    // FIXME: Remove for launch
    [self stubReferendumData];
}

- (void)stubReferendumData
{
#if DEBUG
    NSDictionary *referendumAttributes = @{@"type": @"Referendum",
                                           @"level": @"county",
                                           @"referendumTitle": @"Test Referendum",
                                           @"referendumSubtitle": @"This is a test referendum...",
                                           @"referendumUrl": @"http://votinginfoproject.org"};
    Contest *referendum = [Contest setFromDictionary:referendumAttributes];
    [self addContestsObject:referendum];
#endif
}

- (void) deleteAllData {
    [self deleteContests];
    [self deletePollingLocations];
    [self deleteStates];

    NSManagedObjectContext *moc = [NSManagedObjectContext MR_contextForCurrentThread];
    // get this save off the main thread!
    [moc MR_saveToPersistentStoreAndWait];
}

- (void) deleteStates
{
    for (State *state in self.states) {
        [state MR_deleteEntity];
    }
}

- (void) deletePollingLocations
{
    for (PollingLocation *pl in self.pollingLocations) {
        [pl MR_deleteEntity];
    }
}

- (void) deleteContests
{
    for (Contest *contest in self.contests) {
        [contest MR_deleteEntity];
    }
}

/**
 *  Return an NSError object based on the status strings from the voterInfo API query
 *
 *  @param status NSString status from voterInfo API query
 *  @return NSError with localizedDescription property set to a helpful message
 */
+(NSError*) parseVoterInfoResponseStatus:(NSString*)status
{
    if ([status isEqualToString:APIResponseSuccess]) {
        return nil;
    } else if ([status isEqualToString:APIResponseNoStreetSegmentFound] ||
               [status isEqualToString:APIResponseMultipleStreetSegmentsFound] ||
               [status isEqualToString:APIResponseNoAddressParameter]) {
        return [[NSError alloc] initWithDomain:VIPErrorDomain
                                          code:VIPInvalidUserAddress
                                      userInfo:@{NSLocalizedDescriptionKey: VIPInvalidUserAddressDescription}];
    } else if ([status isEqualToString:APIResponseElectionOver]) {
        return [[NSError alloc] initWithDomain:VIPErrorDomain
                                          code:VIPElectionOver
                                      userInfo:@{NSLocalizedDescriptionKey: VIPElectionOverDescription}];
    } else if ([status isEqualToString:APIResponseElectionUnknown]) {
        return [[NSError alloc] initWithDomain:VIPErrorDomain
                                          code:VIPElectionUnknown
                                      userInfo:@{NSLocalizedDescriptionKey: VIPElectionUnknownDescription}];
    } else {
        return [[NSError alloc] initWithDomain:VIPErrorDomain
                                          code:VIPGenericAPIError
                                      userInfo:@{NSLocalizedDescriptionKey: VIPGenericAPIErrorDescription}];
    }
}

@end
