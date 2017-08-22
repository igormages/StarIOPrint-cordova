//
//  StarIOPrint.m
//  CordovaStarIOPlugin
//
//  Created by Vladyslav on 8/23/16.
//
//

#import "StarIOPrint.h"

#import "RasterDocument.h"
#import "StarBitmap.h"
#import <StarIO/SMPort.h>

#import <sys/time.h>

@implementation StarIOPrint {
    NSArray *_networkPrintersArray;
    PortInfo *_activePrinter;
}

#pragma mark - Plugin methods

- (void)getAvailablePrintersList:(CDVInvokedUrlCommand *)command {
    _networkPrintersArray = [SMPort searchPrinter];
    
    NSArray *availablePrintersDictionaryArray = [self convertPrintersObjectsArrayToDictionaryArray];
    
    if (_networkPrintersArray && [_networkPrintersArray count] > 0) {
        [self.commandDelegate runInBackground:^{
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:availablePrintersDictionaryArray] callbackId:command.callbackId];
        }];
    } else {
        [self.commandDelegate runInBackground:^{
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsArray:availablePrintersDictionaryArray] callbackId:command.callbackId];
        }];
    }
}

- (void)connectToPrinter:(CDVInvokedUrlCommand *)command {
    
    NSString *portName = [command.arguments firstObject];
    
    if (_networkPrintersArray && [_networkPrintersArray count] > 0) {
        for (PortInfo *printer in _networkPrintersArray) {
            if ([printer.portName isEqualToString:portName]) {
                _activePrinter = printer;
                break;
            }
        }
    }
    
    NSLog(@"%@",_activePrinter.portName);
    
    if (_activePrinter) {
        [self.commandDelegate runInBackground:^{
            NSString *printerIP = [NSString stringWithFormat:@"Printer connected successfully! IP: %@", _activePrinter.portName];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:
                                                    CDVCommandStatus_OK messageAsString:printerIP] callbackId:command.callbackId];
        }];
    } else {
        [self.commandDelegate runInBackground:^{
            NSString *printerIP = [NSString stringWithFormat:@"Cannot connect to printer with IP: %@", _activePrinter.portName];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:
                                                    CDVCommandStatus_ERROR messageAsString:printerIP] callbackId:command.callbackId];
        }];
    }
}

- (void)cordovaPOSPrint:(CDVInvokedUrlCommand *)command {
    
    //UIImage *imageToPrint = [self generateImageFromText:[command.arguments firstObject]];
    UIImage *imageToPrint = [UIImage imageWithData:imageData]; //---> Print base64 images
    
    //Then print Image
    
    [self print:imageToPrint completion:^(NSError *error) {
        if (error == nil) {
            [self.commandDelegate runInBackground:^{
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Printed Successfully!"] callbackId:command.callbackId];
            }];
        } else {
            [self.commandDelegate runInBackground:^{
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.localizedDescription] callbackId:command.callbackId];
            }];
        }
    }];
}

#pragma mark - Printer Logic

- (UIImage *)generateImageFromText:(NSString *)text {
    
    UILabel *testLabel = [[UILabel alloc] init];
    testLabel.numberOfLines = 0;
    testLabel.text = text;
    testLabel.font = [UIFont systemFontOfSize:50];
    testLabel.textColor = [UIColor blackColor
                           ];
    testLabel.backgroundColor = [UIColor whiteColor];
    [testLabel sizeToFit];
    
    UIGraphicsBeginImageContext(testLabel.bounds.size);
    [testLabel.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *viewImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return viewImage;
}

- (void)print:(UIImage *)imgData completion:(void(^)(NSError *error))completion {
    NSUserDefaults *pref=[NSUserDefaults standardUserDefaults];
    NSString *tempIPStr= @"10.3.1.172";
    
    if (tempIPStr && tempIPStr.length > 0){
        id portObj = [pref objectForKey:@"PrinterPort"];
        if (!portObj || [portObj integerValue] == 0){
            portObj = @"9100";
        }
        NSString *portString = [NSString stringWithFormat:@"%ld", (long)[portObj integerValue]];
        
        RasterDocument *rasterDoc = [[RasterDocument alloc] initWithDefaults:RasSpeed_Medium endOfPageBehaviour:RasPageEndMode_FeedAndFullCut endOfDocumentBahaviour:RasPageEndMode_FeedAndFullCut topMargin:RasTopMargin_Standard pageLength:0 leftMargin:0 rightMargin:0];
        
        StarBitmap *starbitmap = [[StarBitmap alloc] initWithUIImage:imgData :576 :false];
        
        NSMutableData *commandsToPrint = [[NSMutableData alloc] init];
        NSData *shortcommand = [rasterDoc BeginDocumentCommandData];
        [commandsToPrint appendData:shortcommand];
        
        shortcommand = [starbitmap getImageDataForPrinting:YES];
        [commandsToPrint appendData:shortcommand];
        
        shortcommand = [rasterDoc EndDocumentCommandData];
        [commandsToPrint appendData:shortcommand];
        
        [self sendCommand:commandsToPrint portName:_activePrinter.portName portSettings:portString timeoutMillis:10000 completion:^(NSError *error) {
            completion(error);
        }];
    }
}

- (void)sendCommand:(NSData *)commandsToPrint portName:(NSString *)portName portSettings:(NSString *)portSettings timeoutMillis:(u_int32_t)timeoutMillis completion:(void(^)(NSError *error))completion
{
    int commandSize = (int)commandsToPrint.length;
    unsigned char *dataToSentToPrinter = (unsigned char *)malloc(commandSize);
    [commandsToPrint getBytes:dataToSentToPrinter length:commandSize];
    
    SMPort *starPort = nil;
    @try
    {
        starPort = [SMPort getPort:portName :portSettings :timeoutMillis];
        
        //BOOL online = [starPort getOnlineStatus];
        if (starPort == nil)
        {
            NSError *error = [self generateErrorWithMessage:@"Fail to Open Port.\nRefer to \"getPort API\" in the manual." andCode:1001];
            completion(error);
            return;
        }
        
        StarPrinterStatus_2 status;
        [starPort beginCheckedBlock:&status :2];
        if (status.offline == SM_TRUE) {
            NSError *error = [self generateErrorWithMessage:@"Printer is offline" andCode:1002];
            completion(error);
            return;
        }
        
        struct timeval endTime;
        gettimeofday(&endTime, NULL);
        endTime.tv_sec += 30;
        
        int totalAmountWritten = 0;
        while (totalAmountWritten < commandSize)
        {
            int remaining = commandSize - totalAmountWritten;
            int amountWritten = [starPort writePort:dataToSentToPrinter :totalAmountWritten :remaining];
            totalAmountWritten += amountWritten;
            
            struct timeval now;
            gettimeofday(&now, NULL);
            if (now.tv_sec > endTime.tv_sec)
            {
                break;
            }
        }
        
        if (totalAmountWritten < commandSize)
        {
            NSError *error = [self generateErrorWithMessage:@"Write port timed out" andCode: 1003];
            completion(error);
            return;
        }
        
        starPort.endCheckedBlockTimeoutMillis = 30000;
        [starPort endCheckedBlock:&status :2];
        if (status.offline == SM_TRUE) {
            NSError *error = [self generateErrorWithMessage:@"Printer is offline" andCode:1004];
            completion(error);
            return;
        }
    }
    @catch (PortException *exception)
    {
        NSError *error = [self generateErrorWithMessage:@"Write port timed out" andCode:1005];
        completion(error);
    }
    @finally
    {
        free(dataToSentToPrinter);
        [SMPort releasePort:starPort];
        
        completion(nil);
    }
}

#pragma mark - Private

- (NSArray *)convertPrintersObjectsArrayToDictionaryArray {
    NSMutableArray *dictionaryArray = [[NSMutableArray alloc] init];
    
    for (PortInfo *printer in _networkPrintersArray) {
        NSDictionary *printerDictionary = @{
                                            @"portName":printer.portName,
                                            @"macAddress":printer.macAddress,
                                            @"modelName":printer.modelName
                                            };
        [dictionaryArray addObject:printerDictionary];
    }
    
    return [dictionaryArray copy];
}

- (NSError *)generateErrorWithMessage:(NSString *)messageText andCode:(NSInteger)code {
    NSDictionary *userInfo = @{
                               NSLocalizedDescriptionKey: NSLocalizedString(messageText, nil)
                               };
    NSError *error = [NSError errorWithDomain:@"com.StarIOPrint"
                                         code:code
                                     userInfo:userInfo];
    return error;
}

@end
