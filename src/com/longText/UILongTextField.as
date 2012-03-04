package com.longText
{
import flash.events.Event;
import flash.events.MouseEvent;
import flash.text.TextField;
import flash.text.TextFieldType;
import flash.utils.getTimer;
import flash.utils.setInterval;

import mx.controls.TextInput;
import mx.core.UITextField;

/**
 * Shows only a part of <code>text</code> to avoid performance degradation.
 */
public class UILongTextField extends UITextField
{
	
	/**
	 * Recalculate virtual scrolling if component width have changed by more 
	 * than 10%.
	 */
	protected static const REESTIMATE_WIDTH_CHANGE_RATIO:Number = 0.1;
	
	/**
	 * Maximum length of line that would be seamlessly scrolled up.
	 */
	protected static const CONTINUOUS_SCROLL:int = 5000;
	
	/**
	 * Length of text that is used to estimate the word-wrapped amount of
	 * lines (maxScrollV).
	 */
	protected static const NUM_LINES_TEST_LENGTH:int = 5000;

	public function UILongTextField()
	{
		super();
		
		addListeners();
		createTestField();
	}
	
	protected var lineSeparator:String;
	protected var textLength:int = 0;
	protected var numLinesInText:int = 1;
	protected var numLinesInField:int = 1;
	
	protected var scrollVVirtualPrev:int = 0;
	protected var scrollVVirtual:int = 1;
	protected var maxScrollVVirtualPrev:int = 0;
	protected var maxScrollVVirtual:int = 1;
	
	protected var textInvisibleStartIndex:int = 0;
	protected var textStartIndex:Number = 0;
	protected var realText:String;
	protected var realTextLength:int = 0;
	protected var visibleTextLength:int = 0;
	protected var realScrollV:int = 1;
	
	protected var lastEstimateWidth:Number = 0;
	
	protected var numVisibleLines:int = 1;
	protected var numAverageCharsInTextLine:int = 1;
	
	protected var caretAtTheEnd:Boolean = true;
	protected var selectionBeginIndexVirtual:int = 0;
	protected var selectionEndIndexVirtual:int = 0;
	protected var lastSelectionBeginIndex:int = 0;
	protected var lastSelectionEndIndex:int = 0;
	protected var selectionInFieldIsValid:Boolean = true;
	
	protected var ignoreScrollCounter:int = 0;
	protected var preventIgnoredScrollEvents:Boolean = true;

	override public function get htmlText():String
	{
		return _text;
	}
	
	override public function set htmlText(value:String):void
	{
		throw new Error("htmlText is not supported");
	}
	
	override public function set type(value:String):void
	{
		// Editing is not yet supported.
		super.type = TextFieldType.DYNAMIC;
	}
	
	override public function get maxChars():int
	{
		return 0;
	}
	
	override public function set maxChars(value:int):void
	{
		throw new Error("maxChars is not supported");
	}
	
	override public function get selectionBeginIndex():int {
		return selectionBeginIndexVirtual;
	}
	
	override public function get selectionEndIndex():int {
		return selectionEndIndexVirtual;
	}
	
	public function get superSelectionBeginIndex():int {
		return super.selectionBeginIndex;
	}
	
	public function get superSelectionEndIndex():int {
		return super.selectionEndIndex;
	}
	
	override public function get caretIndex():int {
		return textStartIndex + super.caretIndex;
	}
	
	override public function get numLines():int {
		return numLinesInField;
	}
	
	override public function get maxScrollV():int {
		return maxScrollVVirtual;
	}
	
	override public function get scrollV():int {
		return scrollVVirtual;
	}
	
	override public function set scrollV(value:int):void {
		if (scrollVVirtual < 1)
			scrollVVirtual = 1;
		if (scrollVVirtual > maxScrollVVirtual)
			scrollVVirtual = maxScrollVVirtual;
		if (scrollVVirtual == value)
			return;
		
		// Select all may stay unhandled until now if user scroll to the end 
		// of field and then use context menu.
		if (handleSelectAll())
			return;
		
		scrollVVirtual = value;
		checkVisibleText();
	}
	
	override public function get bottomScrollV():int {
		return scrollVVirtual + numVisibleLines - 1;
	}
	
	override public function set wordWrap(value:Boolean):void {
		if (super.wordWrap == value)
			return;
		
		super.wordWrap = value;
		updateScrollSettings();
		checkVisibleText();
	}
	
	protected var _text:String = "";
	
	protected var testField:TextField;
	
	override public function get text():String
	{
		return _text;
	}
	
	override public function set text(value:String):void
	{
		if (!value)
			value = "";
		if (_text == value)
			return;
		
		// Don't reset virtual scrolling parameters because text might have
		// slightly changed and user expect scrolling to stay on position.
		
		_text = value;
		resetSelection();
		updateTextInfo();
		updateScrollSettings();
		checkVisibleText();
	}
	
	override public function setActualSize(w:Number, h:Number):void {
		super.setActualSize(w, h);
		updateScrollSettings();
		checkVisibleText();
	}
	
	protected function addListeners():void
	{
		addEventListener(Event.SCROLL, scrollHandler, false, int.MAX_VALUE);
	}
	
	protected function createTestField():void
	{
		testField = new TextField();
	}
	
	protected function updateTestField():void
	{
		testField.width = width;
		testField.height = height;
		testField.wordWrap = wordWrap;
		testField.setTextFormat(testField.getTextFormat());
		testField.defaultTextFormat = defaultTextFormat;
	}
	
	protected function resetSelection():void
	{
		selectionBeginIndexVirtual = 0;
		selectionEndIndexVirtual = 0;
	}
	
	protected function readSelection():void
	{
		if (lastSelectionBeginIndex != super.selectionBeginIndex)
			selectionBeginIndexVirtual = textInvisibleStartIndex + super.selectionBeginIndex;
		if (lastSelectionEndIndex != super.selectionEndIndex)
			selectionEndIndexVirtual = textInvisibleStartIndex + super.selectionEndIndex;
		caretAtTheEnd = super.caretIndex > super.selectionBeginIndex ||
			super.selectionBeginIndex == super.selectionEndIndex;
	}
	
	protected function updateSelection():void
	{
		ignoreScrollCounter++;
		var begin:int;
		var end:int;
		if (selectionEndIndexVirtual < textStartIndex ||
			selectionBeginIndexVirtual > textStartIndex + visibleTextLength) {
			var invisibleIndex:int = textStartIndex - textInvisibleStartIndex;
			begin = invisibleIndex;
			end = invisibleIndex;
		} else {
			begin = Math.max(selectionBeginIndexVirtual - textInvisibleStartIndex, 0);
			end = Math.min(selectionEndIndexVirtual - 
				textInvisibleStartIndex, textInvisibleStartIndex + realTextLength);
		}
		if (caretAtTheEnd)
			setSelection(begin, end);
		else
			setSelection(end, begin);
		super.scrollV = realScrollV;
		lastSelectionBeginIndex = super.selectionBeginIndex;
		lastSelectionEndIndex = super.selectionEndIndex;
		ignoreScrollCounter--;
	}
	
	protected function updateTextInfo():void
	{
		textLength = _text.length;
		numLinesInText = getNumLinesInText("\r") + getNumLinesInText("\n");
		numAverageCharsInTextLine = Math.round(textLength / numLinesInText);
	}
	
	protected function getNumLinesInText(separator:String):int
	{
		var lines:int = 1;
		var index:int = 0;
		while (index != -1) {
			index = _text.indexOf(separator, index + 1);
			lines++;
		}
		return lines;
	}
	
	protected function updateScrollSettings():void
	{
		if (!_text) {
			return;
		}
		
		numVisibleLines = getNumVisibleLines();
		numLinesInField = getNumLinesInField();
		maxScrollVVirtualPrev = 0;
		maxScrollVVirtual = estimateMaxScrollV();
		scrollVVirtualPrev = 0;
		scrollVVirtual = Math.min(maxScrollVVirtual, scrollVVirtual);
		
		updateTestField();
	}
	
	protected function getNumLinesInField():int
	{
		if (wordWrap) {
			setTestText(text.substr(0, NUM_LINES_TEST_LENGTH));
			return Math.round(testField.numLines * 
				Math.max(1, textLength / NUM_LINES_TEST_LENGTH));
		} else {
			return numLinesInText;
		}
	}
	
	/**
	 * Returns maximum amount of lines that fit into screen without scrolling.
	 */
	protected function getNumVisibleLines():int
	{
		setTestText("");
		while (testField.bottomScrollV == testField.numLines) {
			setTestText(testField.text + "a\n");
		}
		return testField.bottomScrollV;
	}
	
	protected function checkVisibleText():Boolean
	{
		if (!_text) {
			super.text = "";
			return true;
		}
		
		if (scrollVVirtual == scrollVVirtualPrev && 
			maxScrollVVirtual == maxScrollVVirtualPrev)
			return false;
		
		ignoreScrollCounter++;
		updateTestField();
		if (selectionInFieldIsValid)
			readSelection();
		updateVisibleText();
		updateSelection();
		scrollVVirtualPrev = scrollVVirtual;
		maxScrollVVirtualPrev = maxScrollVVirtual;
		ignoreScrollCounter--;
		selectionInFieldIsValid = true;
		return true;
	}
	
	protected function updateVisibleText():void
	{
		var startIndex:int = 0;
		var lengthNeeded:int = 100;
		var delta:int = scrollVVirtual - scrollVVirtualPrev;
		if (scrollVVirtual == 1) {
			startIndex = 0;
		} else {
			if (scrollVVirtualPrev && delta > 0 && delta <= numVisibleLines) {
				startIndex = textInvisibleStartIndex + getLineOffset(realScrollV - 1 + delta);
			} else if (scrollVVirtualPrev && delta < 0 && delta >= - numVisibleLines) {
				startIndex = countLinesBack(-delta, textStartIndex);
			} else {
				startIndex = getStartIndex();
			}
		}
		var candidate:String = _text.substr(startIndex, lengthNeeded);
		setTestText(candidate);
		
		// We need to distinguish Page DOWN and Ctrl+End (end of document)
		// user actions so we need 1 extra page after the visible page and
		// 1 more line.
		var linesNeeded:int = numVisibleLines * 2 + 2;
		// If lengthRequired was not big enough, get more text.
		while (testField.numLines <= linesNeeded &&
			startIndex + lengthNeeded < textLength) {
			lengthNeeded *= 2;
			candidate = _text.substr(startIndex, lengthNeeded);
			setTestText(candidate);
		}
		
		// If candidate is not long enough to fill numVisibleLines then
		// move startIndex back and set scroll position to the end.
		if (testField.numLines < numVisibleLines && 
			startIndex + lengthNeeded >= textLength) {
			// We're at the end of text and need to scroll back to fill screen.
			var nextStartIndex:int = countLinesBack(
				numVisibleLines - testField.numLines, startIndex);
			lengthNeeded += startIndex - nextStartIndex;
			startIndex = nextStartIndex;
			candidate = _text.substr(startIndex);
			scrollVVirtual = maxScrollVVirtual;
			notifyAboutScrollChange();
		} else if (startIndex + lengthNeeded >= textLength) {
			// Count the lines left to the end and update scrollV precisely.
			var preciseScrollV:int = maxScrollVVirtual -
				Math.max(0, testField.numLines - numVisibleLines);
			if (preciseScrollV != scrollVVirtual) {
				scrollVVirtual = preciseScrollV;
				notifyAboutScrollChange();
			}
		}
		
		// Add some invisible lines before the first visible line to
		// handle scrolling up (including scrolling with selection) with
		// Up, Page Up and Ctrl+Home.
		var linesBeforeNeeded:int = Math.min(scrollVVirtual - 1, numVisibleLines + 1);
		textInvisibleStartIndex = countLinesBack(linesBeforeNeeded, startIndex);
		lengthNeeded += startIndex - textInvisibleStartIndex;
		candidate = _text.substr(textInvisibleStartIndex, lengthNeeded);
		
		textStartIndex = startIndex;
		realText = candidate;
		realTextLength = candidate.length;
		realScrollV = linesBeforeNeeded + 1;
		setTestText(candidate);
		testField.scrollV = realScrollV;
		var lastVisibleLine:int = Math.min(testField.numLines - 1, linesBeforeNeeded + numVisibleLines - 1);
		visibleTextLength = testField.getLineOffset(lastVisibleLine) + 
			testField.getLineLength(lastVisibleLine) -
			testField.getLineOffset(0);
		super.text = candidate;
		super.scrollV = realScrollV;
	}
	
	protected function notifyAboutScrollChange():void
	{
		ignoreScrollCounter++;
		var value:Boolean = preventIgnoredScrollEvents;
		preventIgnoredScrollEvents = false;
		dispatchEvent(new Event(Event.SCROLL));
		preventIgnoredScrollEvents = value;
		ignoreScrollCounter--;
	}
	
	protected function setTestText(string:String):void
	{
		if (testField.text == string)
			return;
		
		testField.text = string;
		testField.defaultTextFormat = defaultTextFormat;
	}
	
	/**
	 * Counts amount of characters needed to fill <code>delta</code> lines
	 * of text before line starting with <code>fromIndex</code> with current
	 * text field settings.
	 */
	protected function countLinesBack(delta:int, fromIndex:int):int
	{
		while (delta > 0 && fromIndex > 0) {
			fromIndex = countLineBack(fromIndex);
			delta--;
		}
		return fromIndex;
	}
	
	protected function countLineBack(fromIndex:int):int
	{
		if (isLineSeparator(_text.charAt(fromIndex - 1)) &&
			isLineSeparator(_text.charAt(fromIndex - 2)))
			return fromIndex - 1;
		
		if (isLineSeparator(_text.charAt(fromIndex - 1)))
			fromIndex--;
		
		var lineStartIndex:int = getLineStartByCharIndex(fromIndex);
		var previousLine:String = _text.substring(lineStartIndex, fromIndex);
		setTestText(previousLine);
		
		var lineOffset:int = testField.getLineOffset(testField.numLines - 1);
		return lineStartIndex + lineOffset;
	}
	
	protected function isLineSeparator(char:String):Boolean
	{
		return char == "\r" || char == "\n";
	}
	
	protected function getLineStartByCharIndex(fromIndex:int):int
	{
		var lineStartIndex:int = Math.max(0, fromIndex - CONTINUOUS_SCROLL);
		var newLineIndex:int = lineStartIndex;
		var lastNewLineIndex:int = lineStartIndex;
		do {
			lastNewLineIndex = newLineIndex;
			newLineIndex = getNewLineIndex(newLineIndex + 1);
		} while (newLineIndex > 0 && newLineIndex < fromIndex)
		return lastNewLineIndex;
	}
	
	protected function getNewLineIndex(fromIndex:int):int
	{
		var rIndex:int = _text.indexOf("\r", fromIndex);
		var nIndex:int = _text.indexOf("\n", fromIndex);
		if (rIndex == -1)
			return nIndex;
		else if (nIndex == -1)
			return rIndex;
		return rIndex < nIndex ? rIndex : nIndex;
	}
	
	protected function getStartIndex():int
	{
		if (wordWrap) {
			var approximateIndex:int = textLength * scrollVVirtual / maxScrollVVirtual;
			var lineStartIndex:int = getLineStartByCharIndex(approximateIndex);
			setTestText(_text.substring(lineStartIndex, approximateIndex));
			return lineStartIndex + testField.getLineOffset(testField.numLines - 1);
		} else {
			var index:int = numAverageCharsInTextLine * (scrollVVirtual - 1);
			// Find first new line and start from it.
			if (index > 0 && !isLineSeparator(_text.charAt(index - 1))) {
				var nextNewLine:int = getNewLineIndex(index);
				if (nextNewLine == -1 || 
					nextNewLine - index > CONTINUOUS_SCROLL) {
					return index;
				}
				index = nextNewLine + 1;
				var firstChar:String = _text.charAt(index);
				if (isLineSeparator(firstChar)) {
					index++;
				}
			}
			return index;
		}
	}
	
	/**
	 * Provides approximate amount of lines current text will take with current
	 * word wrap and field width.
	 */
	protected function estimateMaxScrollV():int {
		return Math.max(1, numLinesInField - numVisibleLines + 1);
	}
	
	/**
	 * Returns true if user has just selected all text via Ctrl+A or
	 * context menu.
	 */
	protected function handleSelectAll():Boolean
	{
		var selectionChanged:Boolean = 
			lastSelectionBeginIndex != super.selectionBeginIndex ||
			lastSelectionEndIndex != super.selectionEndIndex;
		if (selectionChanged && super.selectionBeginIndex == 0 && 
			super.selectionEndIndex == realTextLength &&
			(selectionBeginIndexVirtual != 0 || 
			selectionEndIndexVirtual != textLength)) {
			selectionInFieldIsValid = false;
			selectionBeginIndexVirtual = 0;
			selectionEndIndexVirtual = textLength;
			scrollV = maxScrollV;
			notifyAboutScrollChange();
			return true;
		}
		return false;
	}
	
	/**
	 * Returns true when last user action was moving to the beginning or to 
	 * the end of document with keyboard shortcut.
	 */
	protected function handleBorderOfDocument():Boolean
	{
		if (super.scrollV >= super.maxScrollV - 1) {
			scrollV = maxScrollV;
			notifyAboutScrollChange();
			return true;
		} else if (super.scrollV == 1) {
			scrollV = 1;
			notifyAboutScrollChange();
			return true;
		}
		return false;
	}
	
	protected function scrollHandler(event:Event):void
	{
		if (ignoreScrollCounter > 0) {
			if (super.scrollV != realScrollV)
				super.scrollV = realScrollV;
			if (preventIgnoredScrollEvents)
				event.stopImmediatePropagation();
			return;
		}
		
		if (handleSelectAll() || handleBorderOfDocument()) {
			// Handling this actions includes dispatching scroll event.
			event.stopImmediatePropagation();
			return;
		}
		
		ignoreScrollCounter++;
		scrollV += super.scrollV - realScrollV;
		ignoreScrollCounter--;
	}
	
}
}