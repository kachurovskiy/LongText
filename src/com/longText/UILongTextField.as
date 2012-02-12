package com.longText
{
import flash.events.Event;
import flash.text.TextField;
import flash.utils.getTimer;
import flash.utils.setInterval;

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
	 * Amount of lines user can continuously scroll without artifacts.
	 */
	protected static const CONTINUOUS_SCROLL:int = 1000;

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
	
	override public function set htmlText(value:String):void
	{
		throw new Error("htmlText is not supported");
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
		var startTime:int = getTimer();
		updateTextInfo();
		updateScrollSettings();
		updateVisibleText();
		trace("Set text time - " + (getTimer() - startTime));
	}
	
	override public function setActualSize(w:Number, h:Number):void {
		super.setActualSize(w, h);
		updateScrollSettings();
		updateVisibleText();
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
		numVisibleCharsInLine = getNumVisibleCharsInLine();
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
			return Math.ceil(textLength / numVisibleCharsInLine);
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
	
	/**
	 * Returns maximum amount of chars that fit into screen without scrolling.
	 */
	protected function getNumVisibleCharsInLine():int
	{
		setTestText("");
		testField.wordWrap = true;
		while (testField.numLines <= 1) {
			setTestText(testField.text + "a");
		}
		testField.wordWrap = wordWrap;
		return Math.max(1, testField.text.length - 1);
	}
	
	protected function updateVisibleText():void
	{
		if (!_text) {
			super.text = "";
			return;
		}
		
		if (scrollVVirtual == scrollVVirtualPrev && 
			maxScrollVVirtual == maxScrollVVirtualPrev)
			return;
		
		updateTestField();
		
		super.text = getVisibleText();
		
		scrollVVirtualPrev = scrollVVirtual;
		maxScrollVVirtualPrev = maxScrollVVirtual;
	}
	
	protected function getVisibleText():String
	{
		var startIndex:int = 0;
		var lengthRequired:int = numVisibleCharsInLine * numVisibleLines * 1.5;
		var delta:int = scrollVVirtual - scrollVVirtualPrev;
		if (scrollVVirtual == 1) {
			startIndex = 0;
		} else {
			if (scrollVVirtualPrev && delta > 0 && delta < numVisibleLines) {
				startIndex = textStartIndex + getLineOffset(delta);
			} else if (scrollVVirtualPrev && delta < 0 && delta > - numVisibleLines) {
				startIndex = countLinesBack(-delta, textStartIndex);
			} else {
				startIndex = getStartIndex();
			}
		}
		var candidate:String = _text.substr(startIndex, lengthRequired);
		setTestText(candidate);
		
		// If lengthRequired was not big enough to fill the screen, get more text.
		while (testField.numLines <= numVisibleLines &&
			startIndex + lengthRequired < textLength) {
			lengthRequired *= 2;
			candidate = _text.substr(startIndex, lengthRequired);
			setTestText(candidate);
		}
		
		// If candidate is not long enough to fill numVisibleLines then
		// move startIndex back and set scroll position to the end.
		if (testField.numLines < numVisibleLines && 
			startIndex + lengthRequired >= textLength) {
			// We're at the end of text and need to scroll back to fill screen.
			startIndex = countLinesBack(numVisibleLines - testField.numLines,
				startIndex);
			candidate = _text.substr(startIndex);
			scrollVVirtual = maxScrollVVirtual;
			notifyAboutScrollFix();
		} else if (startIndex + lengthRequired >= textLength) {
			var preciseScrollV:int = maxScrollVVirtual -
				(testField.numLines - numVisibleLines);
			if (preciseScrollV != scrollVVirtual) {
				scrollVVirtual = preciseScrollV;
				notifyAboutScrollFix();
			}
		}
		textStartIndex = startIndex;
		return candidate;
	}
	
	protected function notifyAboutScrollFix():void
	{
		dispatchEvent(new Event(Event.SCROLL));
	}
	
	protected function setTestText(string:String):void
	{
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
		if (_text.charAt(fromIndex - 1) == lineSeparator &&
			_text.charAt(fromIndex - 2) == lineSeparator)
			return fromIndex - 1;
		
		if (_text.charAt(fromIndex - 1) == lineSeparator)
			fromIndex--;
		
		var lineStartIndex:int = getLineStartByCharIndex(fromIndex);
		var previousLine:String = _text.substring(lineStartIndex, fromIndex);
		setTestText(previousLine);
		
		var lineOffset:int = testField.getLineOffset(testField.numLines - 1);
		return lineStartIndex + lineOffset;
	}
	
	protected function getLineStartByCharIndex(fromIndex:int):int
	{
		var lineStartIndex:int = Math.max(0, fromIndex - CONTINUOUS_SCROLL);
		var newLineIndex:int = lineStartIndex;
		var lastNewLineIndex:int = lineStartIndex;
		do {
			lastNewLineIndex = newLineIndex;
			newLineIndex = _text.indexOf(lineSeparator, newLineIndex + 1);
		} while (newLineIndex > 0 && newLineIndex < fromIndex)
		return lastNewLineIndex;
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