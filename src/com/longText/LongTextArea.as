package com.longText
{
import mx.controls.TextArea;
import mx.core.UITextField;
import mx.core.mx_internal;

/**
 * Uses special version of UITextField to allow long texts.
 */
public class LongTextArea extends TextArea
{
	override protected function createInFontContext(classObj:Class):Object {
		if (classObj == UITextField) {
			classObj = UILongTextField;
		}
		return super.createInFontContext(classObj);
	}
}
}