//
//  DTXManagedPlotControllerGroup.m
//  DetoxInstruments
//
//  Created by Leo Natan (Wix) on 02/06/2017.
//  Copyright © 2017 Wix. All rights reserved.
//

#import "DTXManagedPlotControllerGroup.h"
#import "DTXTimelineIndicatorView.h"
#import "DTXPlotRowView.h"
#import "DTXPlotTypeCellView.h"
#import "DTXPlotHostingTableCellView.h"
#import "NSColor+UIAdditions.h"

@interface DTXManagedPlotControllerGroup () <DTXPlotControllerDelegate, NSOutlineViewDelegate, NSOutlineViewDataSource>
{
	NSMutableArray<id<DTXPlotController>>* _managedPlotControllers;
	NSMutableArray<id<DTXPlotController>>* _visiblePlotControllers;
	NSMapTable<id<DTXPlotController>, NSMutableArray<id<DTXPlotController>>*>* _childrenMap;
	
	BOOL _ignoringPlotRangeNotifications;
	DTXTimelineIndicatorView* _timelineView;
	CPTPlotRange* _savedPlotRange;
	CPTPlotRange* _savedGlobalPlotRange;
	NSNumber* _savedHighlight;
	CPTPlotRange* _savedHighlightRange;
	
	id<DTXPlotController> _currentlySelectedPlotController;
}

@property (nonatomic, strong) NSOutlineView* hostingOutlineView;
@property (nonatomic, copy, readonly) NSArray<id<DTXPlotController>>* plotControllers;

@end

@interface NSUserDefaults ()

- (id)_initWithSuiteName:(id)i container:(id)p;

@end

@implementation DTXManagedPlotControllerGroup
{
	__weak DTXRecordingDocument* _document;
}

- (instancetype)initWithHostingOutlineView:(NSOutlineView*)outlineView document:(DTXRecordingDocument*)document
{
	self = [super init];
	
	if(self)
	{
		_document = document;
		
		_managedPlotControllers = [NSMutableArray new];
		_visiblePlotControllers = [NSMutableArray new];
		_childrenMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory];
		
		_hostingOutlineView = outlineView;
		_hostingOutlineView.indentationPerLevel = 0;
		_hostingOutlineView.indentationMarkerFollowsCell = NO;
		_hostingOutlineView.dataSource = self;
		_hostingOutlineView.delegate = self;
		
		_timelineView = [DTXTimelineIndicatorView new];
		_timelineView.translatesAutoresizingMaskIntoConstraints = NO;

		[_hostingOutlineView.enclosingScrollView.superview addSubview:_timelineView positioned:NSWindowAbove relativeTo:_hostingOutlineView.superview.superview];

		[NSLayoutConstraint activateConstraints:@[
												  [_hostingOutlineView.enclosingScrollView.topAnchor constraintEqualToAnchor:_timelineView.topAnchor],
												  [_hostingOutlineView.enclosingScrollView.leadingAnchor constraintEqualToAnchor:_timelineView.leadingAnchor],
												  [_hostingOutlineView.enclosingScrollView.trailingAnchor constraintEqualToAnchor:_timelineView.trailingAnchor],
												  [_hostingOutlineView.enclosingScrollView.bottomAnchor constraintEqualToAnchor:_timelineView.bottomAnchor]
												  ]];
	}
	
	return self;
}

- (NSArray<id<DTXPlotController>> *)plotControllers
{
	return _managedPlotControllers;
}

- (void)setHeaderPlotController:(id<DTXPlotController>)headerPlotController
{
	_headerPlotController = headerPlotController;
	_headerPlotController.delegate = self;
	
	if(_savedGlobalPlotRange)
	{
		[headerPlotController setGlobalPlotRange:_savedGlobalPlotRange];
	}
	
	if(_savedPlotRange)
	{
		[headerPlotController setPlotRange:_savedPlotRange];
	}
}

- (void)setTouchBarPlotController:(id<DTXPlotController>)touchBarPlotController
{
	_touchBarPlotController = touchBarPlotController;
	
	_touchBarPlotController.delegate = self;
	
	if(_savedGlobalPlotRange)
	{
		[_touchBarPlotController setGlobalPlotRange:_savedGlobalPlotRange];
	}
	
	if(_savedPlotRange)
	{
		[_touchBarPlotController setPlotRange:_savedPlotRange];
	}
	
	if(_savedHighlight)
	{
		[_touchBarPlotController shadowHighlightAtSampleTime:_savedHighlight.doubleValue];
	}
	
	if(_savedHighlightRange)
	{
		[_touchBarPlotController shadowHighlightRange:_savedHighlightRange];
	}
}

- (void)addPlotController:(id<DTXPlotController>)plotController
{
	[self insertPlotController:plotController afterPlotController:_managedPlotControllers.lastObject];
}

- (void)removePlotController:(id<DTXPlotController>)plotController
{
	plotController.delegate = nil;
	[_managedPlotControllers removeObject:plotController];
}

- (void)insertPlotController:(id<DTXPlotController>)plotController afterPlotController:(id<DTXPlotController>)afterPlotController
{
	[self _insertPlotController:plotController afterPlotController:afterPlotController parentPlotController:nil inCollection:_managedPlotControllers];
}

- (void)_insertPlotController:(id<DTXPlotController>)plotController afterPlotController:(id<DTXPlotController>)afterPlotController parentPlotController:(id<DTXPlotController>)parentPlotController inCollection:(NSMutableArray<id<DTXPlotController>>*)collection
{
	NSInteger idx;
	
	if(afterPlotController == nil)
	{
		//This will make sure we insert at index 0.
		idx = -1;
	}
	else if(collection.firstObject == afterPlotController)
	{
		idx = 0;
	}
	else if(collection.lastObject == afterPlotController)
	{
		idx = collection.count - 1;
	}
	else
	{
		idx = [collection indexOfObject:afterPlotController];
	}
	
	if(idx == NSNotFound)
	{
		return;
	}
	
	[collection insertObject:plotController atIndex:idx + 1];
	plotController.delegate = self;
	
	if(_savedGlobalPlotRange)
	{
		[plotController setGlobalPlotRange:_savedGlobalPlotRange];
	}
	
	if(_savedPlotRange)
	{
		[plotController setPlotRange:_savedPlotRange];
	}
	
	if(_savedHighlight)
	{
		[plotController shadowHighlightAtSampleTime:_savedHighlight.doubleValue];
	}
	
	if(_savedHighlightRange)
	{
		[plotController shadowHighlightRange:_savedHighlightRange];
	}
	
	[self _noteOutlineViewOfInsertedAtIndex:idx + 1 forItem:parentPlotController];
	
	if(idx == 0 && parentPlotController == nil && _hostingOutlineView.selectedRowIndexes.count == 0)
	{
		[_hostingOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	}
}

- (void)setPlotControllerVisible:(id<DTXPlotController>)plotController
{
	NSLog(@"Visible: %@", plotController.class);
}

- (void)setPlotControllerHidden:(id<DTXPlotController>)plotController
{
	NSLog(@"Hidden: %@", plotController.class);
}

- (void)_noteOutlineViewOfInsertedAtIndex:(NSUInteger)index forItem:(id<DTXPlotController>)item
{
	[_hostingOutlineView beginUpdates];
	[_hostingOutlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:index] inParent:item withAnimation:NSTableViewAnimationEffectNone];
	[_hostingOutlineView endUpdates];
}

- (void)_noteOutlineViewOfRemovedAtIndex:(NSUInteger)index forItem:(id<DTXPlotController>)item
{
	[_hostingOutlineView beginUpdates];
	[_hostingOutlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:index] inParent:item withAnimation:NSTableViewAnimationEffectNone];
	[_hostingOutlineView endUpdates];
}

- (NSMutableArray<id<DTXPlotController>>*)_childrenArrayForPlotController:(id<DTXPlotController>)plotController create:(BOOL)create
{
	NSMutableArray* rv = [_childrenMap objectForKey:plotController];
	
	if(create == YES && rv == nil)
	{
		rv = [NSMutableArray new];
		[_childrenMap setObject:rv forKey:plotController];
	}
	
	return rv;
}

- (NSArray<id<DTXPlotController>>*)childPlotControllersForPlotController:(id<DTXPlotController>)plotController;
{
	return [self _childrenArrayForPlotController:plotController create:YES];
}

- (void)addChildPlotController:(id<DTXPlotController>)childPlotController toPlotController:(id<DTXPlotController>)plotController
{
	NSMutableArray* children = [self _childrenArrayForPlotController:plotController create:YES];
	[self _insertPlotController:childPlotController afterPlotController:children.lastObject parentPlotController:plotController inCollection:children];
}

- (void)insertChildPlotController:(id<DTXPlotController>)childPlotController afterChildPlotController:(id<DTXPlotController>)afterPlotController ofPlotController:(id<DTXPlotController>)plotController
{
	NSMutableArray* children = [self _childrenArrayForPlotController:plotController create:YES];
	[self _insertPlotController:childPlotController afterPlotController:afterPlotController parentPlotController:plotController inCollection:children];
}

- (void)removeChildPlotController:(id<DTXPlotController>)childPlotController ofPlotController:(id<DTXPlotController>)plotController
{
	childPlotController.delegate = nil;
	[_managedPlotControllers removeObject:childPlotController];
}

- (void)_enumerateAllPlotControllersIncludingChildrenIn:(NSMutableArray<id<DTXPlotController>>*)plotControllers usingBlock:(void (NS_NOESCAPE ^)(id<DTXPlotController> obj))block
{
	[plotControllers enumerateObjectsUsingBlock:^(id<DTXPlotController>  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		block(obj);
		
		NSMutableArray<id<DTXPlotController>>* children = [_childrenMap objectForKey:obj];
		if(children != nil)
		{
			[self _enumerateAllPlotControllersIncludingChildrenIn:children usingBlock:block];
		}
	}];
}

- (void)setLocalStartTimestamp:(NSDate*)startTimestamp endTimestamp:(NSDate*)endTimestamp;
{
	_savedPlotRange = [CPTPlotRange plotRangeWithLocation:@0 length:@(endTimestamp.timeIntervalSinceReferenceDate - startTimestamp.timeIntervalSinceReferenceDate)];
	
	_ignoringPlotRangeNotifications = YES;
	[_headerPlotController setPlotRange:_savedPlotRange];
	[_touchBarPlotController setPlotRange:_savedPlotRange];
	[self _enumerateAllPlotControllersIncludingChildrenIn:_managedPlotControllers usingBlock:^(id<DTXPlotController> obj) {
		[obj setPlotRange:_savedPlotRange];
	}];
	
	_ignoringPlotRangeNotifications = NO;
}

- (void)setGlobalStartTimestamp:(NSDate*)startTimestamp endTimestamp:(NSDate*)endTimestamp;
{
	_savedGlobalPlotRange = [CPTPlotRange plotRangeWithLocation:@0 length:@(endTimestamp.timeIntervalSinceReferenceDate - startTimestamp.timeIntervalSinceReferenceDate)];
	
	_ignoringPlotRangeNotifications = YES;
	[_headerPlotController setGlobalPlotRange:_savedGlobalPlotRange];
	[_touchBarPlotController setGlobalPlotRange:_savedGlobalPlotRange];
	[self _enumerateAllPlotControllersIncludingChildrenIn:_managedPlotControllers usingBlock:^(id<DTXPlotController> obj) {
		[obj setGlobalPlotRange:_savedGlobalPlotRange];
	}];

	_ignoringPlotRangeNotifications = NO;
}

- (void)zoomIn
{
	//Zooming in or out one plot controller will propagate to others using the plotController:didChangeToPlotRange: delegate method.
	[_managedPlotControllers.firstObject zoomIn];
}

- (void)zoomOut
{
	//Zooming in or out one plot controller will propagate to others using the plotController:didChangeToPlotRange: delegate method.
	[_managedPlotControllers.firstObject zoomOut];
}

- (void)zoomToFitAllData
{
	//Zooming in or out one plot controller will propagate to others using the plotController:didChangeToPlotRange: delegate method.
	[_managedPlotControllers.firstObject zoomToFitAllData];
}

- (void)plotControllerUserDidClickInPlotBounds:(id<DTXPlotController>)pc
{
	[self _enumerateAllPlotControllersIncludingChildrenIn:_managedPlotControllers usingBlock:^(id<DTXPlotController> obj) {
		if(obj == pc)
		{
			return;
		}
		
		[obj removeHighlight];
	}];
	
	[_hostingOutlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:[_hostingOutlineView rowForItem:pc]] byExtendingSelection:NO];
	[_hostingOutlineView.window makeFirstResponder:_hostingOutlineView];
}

- (void)requiredHeightChangedForPlotController:(id<DTXPlotController>)pc
{
	if(pc == _touchBarPlotController)
	{
		return;
	}
	
	[_hostingOutlineView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndex:[_hostingOutlineView rowForItem:pc]]];
}

#pragma mark DTXPlotControllerDelegate

static BOOL __uglyHackTODOFixThis()
{
	//TODO: Fix
	return [[[NSThread callStackSymbols] description] containsString:@"CPTAnimation"];
}

- (void)plotController:(id<DTXPlotController>)pc didChangeToPlotRange:(CPTPlotRange *)plotRange
{
	if(_ignoringPlotRangeNotifications || __uglyHackTODOFixThis())
	{
		return;
	}
	
	_ignoringPlotRangeNotifications = YES;
	_savedPlotRange = plotRange;
	
	if(pc != _headerPlotController)
	{
		[_headerPlotController setPlotRange:plotRange];
	}
	
	if(pc != _touchBarPlotController)
	{
		[_touchBarPlotController setPlotRange:plotRange];
	}
	
	[self _enumerateAllPlotControllersIncludingChildrenIn:_managedPlotControllers usingBlock:^(id<DTXPlotController> obj) {
		if(obj == pc)
		{
			return;
		}
		
		[obj setPlotRange:plotRange];
	}];
	
	_ignoringPlotRangeNotifications = NO;
}

- (void)plotController:(id<DTXPlotController>)pc didHighlightAtSampleTime:(NSTimeInterval)sampleTime
{
	_savedHighlight = @(sampleTime);
	
	[self _enumerateAllPlotControllersIncludingChildrenIn:_managedPlotControllers usingBlock:^(id<DTXPlotController> obj) {
		if(obj == pc)
		{
			return;
		}
		
		if([obj respondsToSelector:@selector(shadowHighlightAtSampleTime:)])
		{
			[obj shadowHighlightAtSampleTime:sampleTime];
		}
	}];
	
	if([_touchBarPlotController respondsToSelector:@selector(shadowHighlightAtSampleTime:)])
	{
		[_touchBarPlotController shadowHighlightAtSampleTime:sampleTime];
	}
}

- (void)plotController:(id<DTXPlotController>)pc didHighlightRange:(CPTPlotRange*)highlightRange
{
	_savedHighlightRange = highlightRange;
	
	[self _enumerateAllPlotControllersIncludingChildrenIn:_managedPlotControllers usingBlock:^(id<DTXPlotController> obj) {
		if(obj == pc)
		{
			return;
		}
		
		if([obj respondsToSelector:@selector(shadowHighlightAtSampleTime:)])
		{
			[obj shadowHighlightRange:highlightRange];
		}
	}];
	
	if([_touchBarPlotController respondsToSelector:@selector(shadowHighlightAtSampleTime:)])
	{
		[_touchBarPlotController shadowHighlightRange:highlightRange];
	}
}

- (void)plotControllerDidRemoveHighlight:(id<DTXPlotController>)pc
{
	_savedHighlight = nil;
	_savedHighlightRange = nil;
	
	[self _enumerateAllPlotControllersIncludingChildrenIn:_managedPlotControllers usingBlock:^(id<DTXPlotController> obj) {
		if(obj == pc)
		{
			return;
		}
		
		if([obj respondsToSelector:@selector(removeHighlight)])
		{
			[obj removeHighlight];
		}
	}];
	
	if([_touchBarPlotController respondsToSelector:@selector(removeHighlight)])
	{
		[_touchBarPlotController removeHighlight];
	}
}

#pragma mark NSOutlineView Data Source & Delegate

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if(item == nil)
	{
		return _managedPlotControllers.count;
	}
	
	return [[self _childrenArrayForPlotController:item create:NO] count];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [[self _childrenArrayForPlotController:item create:NO] count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	if(item == nil)
	{
		return _managedPlotControllers[index];
	}
	
	id<DTXPlotController> plotController = item;
	return [[self _childrenArrayForPlotController:plotController create:NO] objectAtIndex:index];
}

- (NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item
{
	return [DTXPlotRowView new];
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	id<DTXPlotController> controller = item;
	
	if([tableColumn.identifier isEqualToString:@"DTXTitleColumnt"])
	{
		DTXPlotTypeCellView* cell = [outlineView makeViewWithIdentifier:@"InfoTableViewCell" owner:nil];
		cell.textField.font = controller.titleFont;
		cell.textField.stringValue = controller.displayName;
		cell.textField.toolTip = controller.toolTip ?: controller.displayName;
		cell.textField.allowsDefaultTighteningForTruncation = YES;
		cell.imageView.image = controller.displayIcon;
		cell.secondaryImageView.image = controller.secondaryIcon;
		cell.secondaryImageView.hidden = controller.secondaryIcon == nil;
		cell.toolTip = controller.toolTip ?: controller.displayName;
		
		if(controller.legendTitles.count > 1)
		{
			cell.topLegendTextField.hidden = cell.bottomLegendTextField.hidden = NO;
			cell.topLegendTextField.attributedStringValue = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@", controller.legendTitles.firstObject ?: @""] attributes:@{NSForegroundColorAttributeName: controller.legendColors.firstObject ?: NSColor.labelColor}];
			cell.bottomLegendTextField.attributedStringValue = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@", controller.legendTitles.lastObject ?: @""] attributes:@{NSForegroundColorAttributeName: controller.legendColors.lastObject ?: NSColor.labelColor}];
		}
		else
		{
			cell.topLegendTextField.hidden = cell.bottomLegendTextField.hidden = YES;
		}
		
		return cell;
	}
	else if([tableColumn.identifier isEqualToString:@"DTXGraphColumn"])
	{
		DTXPlotHostingTableCellView* cell = [outlineView makeViewWithIdentifier:@"PlotHostingTableViewCell" owner:nil];
		cell.plotController = controller;
		return cell;
	}
	
	return nil;
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item
{
	return [item requiredHeight];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	return [item canReceiveFocus];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	[self _enumerateAllPlotControllersIncludingChildrenIn:_managedPlotControllers usingBlock:^(id<DTXPlotController> obj) {
		[obj removeHighlight];
	}];
	
	id<DTXPlotController> plotController = [_hostingOutlineView itemAtRow:_hostingOutlineView.selectedRow];
	_currentlySelectedPlotController = plotController;
	
	if(plotController == nil)
	{
		return;
	}
	
	[self.delegate managedPlotControllerGroup:self didSelectPlotController:plotController];
}

- (void)outlineViewItemDidExpand:(NSNotification *)notification
{
	//Tell the system to precache the whole outline area.
	_hostingOutlineView.preparedContentRect = _hostingOutlineView.bounds;
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification
{
	//Tell the system to precache the whole outline area.
	_hostingOutlineView.preparedContentRect = _hostingOutlineView.bounds;
}

@end
