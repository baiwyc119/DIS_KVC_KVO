//
//  NSKeyValueSlowSetter.m
//  DIS_KVC_KVO
//
//  Created by renjinkui on 2017/3/9.
//  Copyright © 2017年 JK. All rights reserved.
//

#import "NSKeyValueSlowSetter.h"

@implementation NSKeyValueSlowSetter

- (id)initWithContainerClassID:(id)containerClassID key:(NSString *)key containerIsa:(Class)containerIsa {
    Method setValueForKeyMethod = class_getInstanceMethod(containerIsa, @selector(setValue:forKey:));
    void *arguments[3] = {NULL};
    arguments[0] = key;
    self = [super initWithContainerClassID:containerClassID key:key implementation:method_getImplementation(setValueForKeyMethod) selector:@selector(valueForKey:) extraArguments:arguments count:1];
    return self;
}

@end