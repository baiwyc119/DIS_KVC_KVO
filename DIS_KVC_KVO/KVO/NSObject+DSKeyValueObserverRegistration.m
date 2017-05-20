//
//  DSObject+DSKeyValueObserverRegistration.m
//  DIS_KVC_KVO
//
//  Created by renjinkui on 2017/1/11.
//  Copyright © 2017年 JK. All rights reserved.
//

#import "NSObject+DSKeyValueObserverRegistration.h"
#import "DSKeyValueProperty.h"
#import "DSKeyValueContainerClass.h"
#import "DSKeyValueObservance.h"
#import "DSKeyValueObservationInfo.h"
#import "DSKeyValueChangeDictionary.h"
#import "DSKeyValuePropertyCreate.h"
#import "DSKeyValueObserverCommon.h"
#import "NSObject+DSKeyValueObservingPrivate.h"
#import "NSObject+DSKeyValueObserverNotification.h"

pthread_mutex_t _DSKeyValueObserverRegistrationLock = PTHREAD_RECURSIVE_MUTEX_INITIALIZER;
pthread_t _DSKeyValueObserverRegistrationLockOwner = NULL;
BOOL _DSKeyValueObserverRegistrationEnableLockingAssertions;

NSString *const DSKeyValueChangeOriginalObservableKey = @"originalObservable";
NSString *const DSKeyValueChangeKindKey = @"kind";
NSString *const DSKeyValueChangeNewKey = @"new";
NSString *const DSKeyValueChangeOldKey = @"old";
NSString *const DSKeyValueChangeIndexesKey = @"indexes";
NSString *const DSKeyValueChangeNotificationIsPriorKey = @"notificationIsPrior";

void DSKeyValueObserverRegistrationLockUnlock() {
    _DSKeyValueObserverRegistrationLockOwner = NULL;
    pthread_mutex_unlock(&_DSKeyValueObserverRegistrationLock);
}

void DSKeyValueObserverRegistrationLockLock() {
    pthread_mutex_lock(&_DSKeyValueObserverRegistrationLock);
    _DSKeyValueObserverRegistrationLockOwner = pthread_self();
}

void DSKeyValueObservingAssertRegistrationLockNotHeld() {
    if(_DSKeyValueObserverRegistrationEnableLockingAssertions && _DSKeyValueObserverRegistrationLockOwner == pthread_self()) {
        assert(pthread_self() != _DSKeyValueObserverRegistrationLockOwner);
    }
}

@implementation NSObject (DSKeyValueObserverRegistration)

- (void)d_addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(DSKeyValueObservingOptions)options context:(void *)context {
    pthread_mutex_lock(&_DSKeyValueObserverRegistrationLock);
    _DSKeyValueObserverRegistrationLockOwner = pthread_self();
    
    DSKeyValueProperty * property = DSKeyValuePropertyForIsaAndKeyPath(self.class,keyPath);
    
    [self _d_addObserver:observer forProperty:property options:options context:context];
    
    pthread_mutex_unlock(&_DSKeyValueObserverRegistrationLock);
}

- (void)_d_addObserver:(id)observer forProperty:(DSKeyValueProperty *)property options:(int)options context:(void *)context {
    if(options & DSKeyValueObservingOptionInitial) {
        NSString *keyPath = [property keyPath];
        _DSKeyValueObserverRegistrationLockOwner = NULL;
        pthread_mutex_unlock(&_DSKeyValueObserverRegistrationLock);
        
        id newValue = nil;
        if (options & DSKeyValueObservingOptionNew) {
            newValue = [self valueForKeyPath:keyPath];
            if (!newValue) {
                newValue = [NSNull null];
            }
        }
        
        DSKeyValueChangeDictionary *changeDictionary = nil;
        DSKeyValueChangeDetails changeDetails = {0};
        changeDetails.kind = DSKeyValueChangeSetting;
        changeDetails.oldValue = nil;
        changeDetails.newValue = newValue;
        changeDetails.indexes = nil;
        changeDetails.extraData = nil;
        
        DSKeyValueNotifyObserver(observer,keyPath, self, context, nil, NO,changeDetails, &changeDictionary);
        
        [changeDictionary release];
        
        pthread_mutex_lock(&_DSKeyValueObserverRegistrationLock);
        _DSKeyValueObserverRegistrationLockOwner = pthread_self();
    }
    
    DSKeyValueObservationInfo *oldObservationInfo = _DSKeyValueRetainedObservationInfoForObject(self,property.containerClass);
    
    BOOL cacheHit = NO;
    DSKeyValueObservance *addedObservance = nil;
    id originalObservable = nil;
    
    DSKeyValueObservingTSD *TSD = NULL;
    if(options & DSKeyValueObservingOptionNew) {
        TSD = _CFGetTSD(DSKeyValueObservingTSDKey);
    }
    if (TSD) {
        originalObservable = TSD->implicitObservanceAdditionInfo.object;
    }
    
    DSKeyValueObservationInfo *newObservationInfo = _DSKeyValueObservationInfoCreateByAdding(oldObservationInfo, observer, property, options, context, originalObservable,&cacheHit,&addedObservance);
    
    _DSKeyValueReplaceObservationInfoForObject(self,property.containerClass,oldObservationInfo,newObservationInfo);
    
    [property object:self didAddObservance:addedObservance recurse:YES];
    
    Class isaForAutonotifying = [property isaForAutonotifying];
    if(isaForAutonotifying) {
        Class cls = object_getClass(self);
        if(cls != isaForAutonotifying) {
            object_setClass(self,isaForAutonotifying);
        }
    }
    
    [newObservationInfo release];
    [oldObservationInfo release];
}


- (void)d_removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath context:(nullable void *)context {
    DSKeyValueObservingTSD *TSD = _CFGetTSD(DSKeyValueObservingTSDKey);
    if (!TSD) {
        TSD = (DSKeyValueObservingTSD *)NSAllocateScannedUncollectable(sizeof(DSKeyValueObservingTSD));
        _CFSetTSD(DSKeyValueObservingTSDKey, TSD, DSKeyValueObservingTSDDestroy);
    }

    DSKeyValueObservingTSD backTSD = *(TSD);
    TSD->implicitObservanceRemovalInfo.context = context;
    TSD->implicitObservanceRemovalInfo.flag = YES;
    
    [self d_removeObserver:observer forKeyPath:keyPath];
    
    *(TSD) = backTSD;
}

- (void)d_removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath {
    pthread_mutex_lock(&_DSKeyValueObserverRegistrationLock);
    _DSKeyValueObserverRegistrationLockOwner = pthread_self();
    
    DSKeyValueProperty * property = DSKeyValuePropertyForIsaAndKeyPath(self.class,keyPath);
    
    [self _d_removeObserver:observer forProperty:property];
    
    pthread_mutex_unlock(&_DSKeyValueObserverRegistrationLock);
}

- (void)_d_removeObserver:(id)observer forProperty:(DSKeyValueProperty *)property {
    DSKeyValueObservationInfo *oldObservationInfo = _DSKeyValueRetainedObservationInfoForObject(self, property.containerClass);
    if (oldObservationInfo) {
        void *context = NULL;
        BOOL flag = NO;
        id originalObservable = nil;
        BOOL cacheHit = NO;
        DSKeyValueObservance *removalObservance = nil;
        
        DSKeyValueObservingTSD *TSD = _CFGetTSD(DSKeyValueObservingTSDKey);
        if (TSD && TSD->implicitObservanceRemovalInfo.relationshipObject == self && TSD->implicitObservanceRemovalInfo.observer == observer && [TSD->implicitObservanceRemovalInfo.keyPathFromRelatedObject isEqualToString:property.keyPath]) {
            originalObservable = TSD->implicitObservanceRemovalInfo.object;
            context = TSD->implicitObservanceRemovalInfo.context;
            flag = TSD->implicitObservanceRemovalInfo.flag;
        }
        
        DSKeyValueObservationInfo *newObservationInfo = _DSKeyValueObservationInfoCreateByRemoving(oldObservationInfo, observer, property, context, flag, originalObservable, &cacheHit, &removalObservance);
        
        if (removalObservance) {
            [removalObservance retain];
            
            _DSKeyValueReplaceObservationInfoForObject(self, property.containerClass, oldObservationInfo, newObservationInfo);
            
            [property object:self didRemoveObservance:removalObservance recurse:YES];
            
            if (!newObservationInfo) {
                if (object_getClass(self) != property.containerClass.originalClass) {
                    object_setClass(self, property.containerClass.originalClass);
                }
            }
            
            [removalObservance release];
            [newObservationInfo release];
            [oldObservationInfo release];
            
            return;
        }
        //没有找到对应的observance，继续往下走，报Cannot remove an observer...异常
    }

    [NSException raise:NSRangeException format:@"Cannot remove an observer <%@ %p> for the key path \"%@\" from <%@ %p> because it is not registered as an observer.",[observer class], observer, property.keyPath, self.class, self];
}

@end


