//
//  UICollectionViewFlowLayout+Add.m
//  test
//
//  Created by RENREN on 2018/4/9.
//  Copyright © 2018年 RENREN. All rights reserved.
//

#import "UICollectionViewFlowLayout+Add.h"
#import <objc/runtime.h>

@implementation UICollectionViewFlowLayout (Add)

+(void)initialize{
    if ([UIDevice currentDevice].systemVersion.floatValue >0 && [UIDevice currentDevice].systemVersion.floatValue<9.0) {
        //针对ios9以下头部悬浮兼容处理
        Method oldMetod1 = class_getInstanceMethod(self, @selector(layoutAttributesForElementsInRect:));
        Method newMethod1 = class_getInstanceMethod(self, @selector(extra_layoutAttributesForElementsInRect:));
        Method oldMetod2 = class_getInstanceMethod(self, @selector(shouldInvalidateLayoutForBoundsChange:));
        Method newMethod2 = class_getInstanceMethod(self, @selector(extra_shouldInvalidateLayoutForBoundsChange:));
        method_exchangeImplementations(oldMetod1, newMethod1);
        method_exchangeImplementations(oldMetod2, newMethod2);
    }
}

-(NSArray<UICollectionViewLayoutAttributes *> *)extra_layoutAttributesForElementsInRect:(CGRect)rect{
    //不需要悬浮或者水平滚动的
    if (!self.sectionHeadersPinToVisibleBoundsAll || self.scrollDirection == UICollectionViewScrollDirectionHorizontal ) {
        return [self extra_layoutAttributesForElementsInRect:rect];
    }
    //悬浮适配
    //UICollectionViewLayoutAttributes:我称它为collectionView中的item(包括cell和header、footer这些)的《结构信息》
    //截取到父类所返回的数组(里面放的是当前屏幕所能展示的item的结构信息),并转化成可变数组
    NSMutableArray<UICollectionViewLayoutAttributes *> *superArr = [[self extra_layoutAttributesForElementsInRect:rect] mutableCopy];
    //创建存索引的数组,无符号(正整数),无序(不能通过下标取值),不可重复(重复的话会自动过滤)
    NSMutableIndexSet *noneHeaderSections = [NSMutableIndexSet indexSet];
    //遍历superArray,得到一个当前屏幕中所有的section数组
    [superArr enumerateObjectsUsingBlock:^(UICollectionViewLayoutAttributes * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.representedElementCategory == UICollectionElementCategoryCell) {
            [noneHeaderSections addIndex:obj.indexPath.section];
        }
    }];
    //遍历superArray,将当前屏幕中拥有的header的section从数组中移除,得到一个当前屏幕中没有header的section数组
    //正常情况下,随着手指往上移,header脱离屏幕会被系统回收而cell尚在,也会触发该方法
    [superArr enumerateObjectsUsingBlock:^(UICollectionViewLayoutAttributes * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj.representedElementKind isEqualToString:UICollectionElementKindSectionHeader] && [noneHeaderSections containsIndex:obj.indexPath.section]) {
            [noneHeaderSections removeIndex:obj.indexPath.section];
        }
    }];
    //遍历当前屏幕中没有header的section数组
    [noneHeaderSections enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        //取到当前section中第一个item的indexPath
        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:0 inSection:idx];
        //获取当前section在正常情况下已经离开屏幕的header结构信息
        UICollectionViewLayoutAttributes *attributes = [self layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader atIndexPath:indexPath];
        //如果当前分区确实有因为离开屏幕而被系统回收的header
        if (attributes) {
            //将该header结构信息重新加入到superArray中去
            [superArr addObject:attributes];
        }
    }];
     //遍历superArray,改变header结构信息中的参数,使它可以在当前section还没完全离开屏幕的时候一直显示
    [superArr enumerateObjectsUsingBlock:^(UICollectionViewLayoutAttributes * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        @autoreleasepool {
            //如果当前item是header
            if ([obj.representedElementKind isEqualToString:UICollectionElementKindSectionHeader]) {
                //得到当前header所在分区的cell的数量
                NSInteger numberOfItemsInSection = [self.collectionView numberOfItemsInSection:obj.indexPath.section];
                //得到第一个item的indexPath
                NSIndexPath *firstItemIndexPath = [NSIndexPath indexPathForItem:0 inSection:obj.indexPath.section];
                //得到最后一个item的indexPath
                NSIndexPath *lastItemIndexPath = [NSIndexPath indexPathForItem:MAX(0, numberOfItemsInSection-1) inSection:obj.indexPath.section];
                //得到第一个item和最后一个item的结构信息
                UICollectionViewLayoutAttributes *firstItemAttributes, *lastItemAttributes;
                if (numberOfItemsInSection>0)
                {
                    //cell有值,则获取第一个cell和最后一个cell的结构信息
                    firstItemAttributes = [self layoutAttributesForItemAtIndexPath:firstItemIndexPath];
                    lastItemAttributes = [self layoutAttributesForItemAtIndexPath:lastItemIndexPath];
                }else{
                    //cell没值,就新建一个UICollectionViewLayoutAttributes
                    firstItemAttributes = [UICollectionViewLayoutAttributes new];
                    //然后模拟出在当前分区中的唯一一个cell,cell在header的下面,高度为0,还与header隔着可能存在的sectionInset的top
                    CGFloat y = CGRectGetMaxY(obj.frame)+self.sectionInset.top;
                    firstItemAttributes.frame = CGRectMake(0, y, 0, 0);
                    //因为只有一个cell,所以最后一个cell等于第一个cell
                    lastItemAttributes = firstItemAttributes;
                }
                //获取当前header的frame
                CGRect rect = obj.frame;
                //当前的滑动距离 + collection本身相对位置的Y值
                CGFloat offset = self.collectionView.contentOffset.y;
                //第一个cell的y值 - 当前header的高度 - 可能存在的sectionInset的top
                CGFloat headerY = firstItemAttributes.frame.origin.y - rect.size.height - self.sectionInset.top;
                //哪个大取哪个,保证header悬停
                //针对当前header基本上都是offset更加大,针对下一个header则会是headerY大,各自处理
                CGFloat maxY = MAX(offset,headerY);
                //最后一个cell的y值 + 最后一个cell的高度 + 可能存在的sectionInset的bottom - 当前header的高度
                //当当前section的footer或者下一个section的header接触到当前header的底部,计算出的headerMissingY即为有效值
                CGFloat headerMissingY = CGRectGetMaxY(lastItemAttributes.frame) + self.sectionInset.bottom - rect.size.height;
                //给rect的y赋新值,因为在最后消失的临界点要跟谁消失,所以取小
                rect.origin.y = MIN(maxY,headerMissingY);
                //给header的结构信息的frame重新赋值
                obj.frame = rect;
                //如果按照正常情况下,header离开屏幕被系统回收,而header的层次关系又与cell相等,如果不去理会,会出现cell在header上面的情况
                //通过打印可以知道cell的层次关系zIndex数值为0,我们可以将header的zIndex设置成1,如果不放心,也可以将它设置成非常大,这里随便填了个20
                obj.zIndex = 20;
            }
        }
    }];
    //返回新值
    return [superArr copy];
}

-(BOOL)extra_shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds{
    //不需要悬浮或者水平滚动的
    if (!self.sectionHeadersPinToVisibleBoundsAll || self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
        return [self extra_shouldInvalidateLayoutForBoundsChange:newBounds];
    }
    return YES;;
}

-(void)setSectionHeadersPinToVisibleBoundsAll:(BOOL)sectionHeadersPinToVisibleBoundsAll{
    if (@available(iOS 9.0, *)) {
        self.sectionHeadersPinToVisibleBounds = sectionHeadersPinToVisibleBoundsAll;
    } 
    objc_setAssociatedObject(self, @selector(sectionHeadersPinToVisibleBoundsAll), @(sectionHeadersPinToVisibleBoundsAll), OBJC_ASSOCIATION_ASSIGN);
}

-(BOOL)sectionHeadersPinToVisibleBoundsAll{
    return [objc_getAssociatedObject(self, _cmd) boolValue];
}




@end
