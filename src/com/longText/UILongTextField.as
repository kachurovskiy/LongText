package com.longText
{
import flash.text.TextField;

import mx.core.UITextField;

/**
 * Shows only a part of <code>text</code> to avoid performance degradation.
 */
public class UILongTextField extends UITextField
{
	
	/**
	 * Virtualization logic starts working if <code>text</code> is longer.
	 */
	public static const LONG_TEXT_LENGTH:int = 50 * 1024 * 1024;
	
	/**
	 * Recalculate virtual scrolling if component width have changed by more 
	 * than 10%.
	 */
	protected static const REESTIMATE_WIDTH_CHANGE_RATIO:Number = 0.1;
	
	/**
	 * Amount of lines user can continuously scroll without artifacts.
	 */
	protected static const CONTINUOUS_SCROLL:int = 10000;

	public function UILongTextField()
	{
		super();
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
	
	protected var textStartIndex:Number = 0;
	
	protected var lastEstimateWidth:Number = 0;
	
	protected var numVisibleLines:int = 1;
	protected var numVisibleCharsInLine:int = 1;
	protected var numAverageCharsInTextLine:int = 1;
	
	protected var _virtual:Boolean = false;
	
	[Bindable("textChange")]
	public function get virtual():Boolean {
		return _virtual;
	}
	
	override public function set htmlText(value:String):void
	{
		throw new Error("htmlText is not supported");
	}
	
	override public function get numLines():int {
		return _virtual ? numLinesInField : super.numLines;
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
		
		scrollVVirtual = value;
		updateVisibleText();
	}
	
	override public function get bottomScrollV():int {
		return scrollVVirtual + numVisibleLines - 1;
	}
	
	override public function set wordWrap(value:Boolean):void {
		if (super.wordWrap == value)
			return;
		
		super.wordWrap = value;
		updateScrollSettings();
		updateVisibleText();
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
		if (value.indexOf("\r\n") >= 0)
			value = value.replace(/\r\n/g, "\r");
		if (_text == value)
			return;
		
		// Don't reset virtual scrolling parameters because text might have
		// slightly changed and user expect scrolling to stay on position.
		
		_text = value;
		updateTextInfo();
		
		// If text is not long enough don't start virtualization.
		if (!multiline || value.length <= LONG_TEXT_LENGTH) {
			_virtual = false;
			super.text = value;
			return;
		}
		
		_virtual = true;
		updateScrollSettings();
		updateVisibleText();
	}
	
	protected function createTestField():void
	{
		testField = new TextField();
	}
	
	protected function updateTextInfo():void
	{
		textLength = _text.length;
		var numSlashR:int = getNumLinesInText("\r");
		var numSlashN:int = getNumLinesInText("\n");
		if (numSlashR >= numSlashN) {
			lineSeparator = "\r";
			numLinesInText = numSlashR;
		} else {
			lineSeparator = "\n";
			numLinesInText = numSlashN;
		}
		numAverageCharsInTextLine = Math.round(textLength / numLinesInText);
	}
	
	protected function getNumLinesInText(separator:String):int
	{
		var lines:int = 0;
		var index:int = 0;
		while (index != -1) {
			index = _text.indexOf(separator, index + 1);
			lines++;
		}
		return lines;
	}
	
	protected function updateScrollSettings():void
	{
		numVisibleLines = getNumVisibleLines();
		numVisibleCharsInLine = getNumVisibleCharsInLine();
		numLinesInField = getNumLinesInField();
		maxScrollVVirtualPrev = 0;
		maxScrollVVirtual = estimateMaxScrollV();
		scrollVVirtualPrev = 0;
		scrollVVirtual = Math.min(maxScrollVVirtual, scrollVVirtual);
		
		testField.width = width;
		testField.height = height;
		testField.wordWrap = wordWrap;
		testField.setTextFormat(getTextStyles());
	}
	
	protected function getNumLinesInField():int
	{
		if (wordWrap) {
			return Math.ceil(textLength / numVisibleCharsInLine);
		} else {
			return numLinesInText;
		}
	}
	
	/**
	 * Returns minimum amount of lines that do not fit into screen without 
	 * scrolling.
	 */
	protected function getNumVisibleLines():int
	{
		// TODO
		return Math.ceil(height / 5);
	}
	
	/**
	 * Calculates minimum amount of chars that do not fit into one screen 
	 * with word wrap and current text format.
	 */
	protected function getNumVisibleCharsInLine():int
	{
		// TODO
		return Math.ceil(width / 3);
	}
	
	protected function updateVisibleText():void
	{
		if (scrollVVirtual == scrollVVirtualPrev && 
			maxScrollVVirtual == maxScrollVVirtualPrev)
			return;
		
		super.text = getVisibleText();
		
		scrollVVirtualPrev = scrollVVirtual;
		maxScrollVVirtualPrev = maxScrollVVirtual;
	}
	
	protected function getVisibleText():String
	{
		var startIndex:int = 0;
		var lengthRequired:int = 1;
		var delta:int = scrollVVirtual - scrollVVirtualPrev;
		if (wordWrap) {
			if (scrollVVirtualPrev && delta > 0 && delta < numVisibleLines) {
				startIndex = textStartIndex + getLineOffset(delta);
			} else if (scrollVVirtualPrev && delta < 0 && delta > - numVisibleLines) {
				startIndex = textStartIndex - countWrappedLinesBack(-delta, 
					textStartIndex);
			} else {
				startIndex = getStartIndex();
			}
			lengthRequired = numVisibleCharsInLine * numVisibleLines;
		} else {
			var index:int = startIndex;
			var linesFound:int = 0;
			while (index != -1 && linesFound < numVisibleLines) {
				index = _text.indexOf(lineSeparator, index + 1);
				linesFound++;
			}
			lengthRequired = index == -1 ? textLength - startIndex : index;
		}
		textStartIndex = startIndex;
		return _text.substr(startIndex, lengthRequired);
	}
	
	/**
	 * Counts amount of characters needed to fill <code>delta</code> lines
	 * of text before line starting with <code>fromIndex</code> with current
	 * text field settings.
	 */
	protected function countWrappedLinesBack(delta:int, fromIndex:int):int
	{
		if (delta == 0)
			return 0;
		var index:int = fromIndex - 1;
		// Not optimal, refactor if it will be a problem.
		while (index > 0) {
			var testText:String = _text.substring(index, fromIndex + 1);
			testField.text = testText;
			if (testField.numLines > delta + 1) {
				return fromIndex - index + 1;
			}
			index--;
		}
		return fromIndex;
	}
	
	protected function getStartIndex():int
	{
		if (wordWrap) {
			return textLength * (scrollVVirtual - 1) / maxScrollVVirtual;
		} else {
			var index:int = numAverageCharsInTextLine * (scrollVVirtual - 1);
			// Find first new line and start from it.
			if (index > 0 && _text.charAt(index - 1) != lineSeparator) {
				index = _text.indexOf(lineSeparator, index) + 1;
				var firstChar:String = _text.charAt(index);
				if (firstChar == lineSeparator) {
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
	
}
}