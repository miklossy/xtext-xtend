/*******************************************************************************
 * Copyright (c) 2013 itemis AG (http://www.itemis.eu) and others.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *******************************************************************************/
package org.eclipse.xtend.core.macro.declaration

import java.util.Map
import java.util.concurrent.CancellationException
import javax.inject.Inject
import org.eclipse.emf.ecore.EObject
import org.eclipse.xtend.core.jvmmodel.IXtendJvmAssociations
import org.eclipse.xtend.core.macro.CompilationContextImpl
import org.eclipse.xtend.core.xtend.XtendClass
import org.eclipse.xtend.core.xtend.XtendConstructor
import org.eclipse.xtend.core.xtend.XtendField
import org.eclipse.xtend.core.xtend.XtendFile
import org.eclipse.xtend.core.xtend.XtendFunction
import org.eclipse.xtend.core.xtend.XtendMember
import org.eclipse.xtend.core.xtend.XtendParameter
import org.eclipse.xtend.core.xtend.XtendTypeDeclaration
import org.eclipse.xtend.lib.macro.declaration.CompilationStrategy
import org.eclipse.xtend.lib.macro.declaration.CompilationUnit
import org.eclipse.xtend.lib.macro.declaration.MutableClassDeclaration
import org.eclipse.xtend.lib.macro.declaration.MutableMemberDeclaration
import org.eclipse.xtend.lib.macro.declaration.MutableNamedElement
import org.eclipse.xtend.lib.macro.declaration.MutableParameterDeclaration
import org.eclipse.xtend.lib.macro.declaration.MutableTypeDeclaration
import org.eclipse.xtend.lib.macro.declaration.MutableTypeParameterDeclaration
import org.eclipse.xtend.lib.macro.declaration.Type
import org.eclipse.xtend.lib.macro.declaration.TypeReference
import org.eclipse.xtend.lib.macro.declaration.Visibility
import org.eclipse.xtend.lib.macro.services.Problem
import org.eclipse.xtend.lib.macro.services.ProblemSupport
import org.eclipse.xtend.lib.macro.services.TypeReferenceProvider
import org.eclipse.xtext.common.types.JvmAnnotationType
import org.eclipse.xtext.common.types.JvmConstructor
import org.eclipse.xtext.common.types.JvmDeclaredType
import org.eclipse.xtext.common.types.JvmEnumerationType
import org.eclipse.xtext.common.types.JvmExecutable
import org.eclipse.xtext.common.types.JvmField
import org.eclipse.xtext.common.types.JvmFormalParameter
import org.eclipse.xtext.common.types.JvmGenericType
import org.eclipse.xtext.common.types.JvmIdentifiableElement
import org.eclipse.xtext.common.types.JvmMember
import org.eclipse.xtext.common.types.JvmOperation
import org.eclipse.xtext.common.types.JvmPrimitiveType
import org.eclipse.xtext.common.types.JvmType
import org.eclipse.xtext.common.types.JvmTypeParameter
import org.eclipse.xtext.common.types.JvmTypeReference
import org.eclipse.xtext.common.types.JvmVisibility
import org.eclipse.xtext.common.types.JvmVoid
import org.eclipse.xtext.common.types.util.TypeReferences
import org.eclipse.xtext.xbase.compiler.TypeReferenceSerializer
import org.eclipse.xtext.xbase.jvmmodel.JvmTypesBuilder
import org.eclipse.xtext.xbase.typesystem.legacy.StandardTypeReferenceOwner
import org.eclipse.xtext.xbase.typesystem.references.LightweightTypeReference
import org.eclipse.xtext.xbase.typesystem.references.OwnedConverter
import org.eclipse.xtext.xbase.typesystem.util.CommonTypeComputationServices

class CompilationUnitImpl implements CompilationUnit {

	override getDocComment() {
		throw new UnsupportedOperationException("Auto-generated function stub")
	}

	override getPackageName() {
		xtendFile.getPackage()
	}

	override getSourceTypeDeclarations() {
		xtendFile.xtendTypes.map[toXtendTypeDeclaration(it)]
	}

	override getSourceClassDeclarations() {
		sourceTypeDeclarations.filter(typeof(XtendClassDeclarationImpl)).toList
	}

	override getGeneratedTypeDeclarations() {
		xtendFile.eResource.contents.filter(typeof(JvmDeclaredType)).map[toTypeDeclaration(it) as MutableTypeDeclaration].
			toList
	}

	override getGeneratedClassDeclarations() {
		generatedTypeDeclarations.filter(typeof(MutableClassDeclaration)).toList
	}
	
	boolean canceled = false
	
	def setCanceled(boolean canceled) {
		this.canceled = canceled
	}
	
	def checkCanceled() {
		if (canceled)
			throw new CancellationException("compilation was canceled.")
	}

	@Property XtendFile xtendFile
	@Inject CommonTypeComputationServices services;
	@Inject TypeReferences typeReferences
	@Inject JvmTypesBuilder typesBuilder
	@Inject TypeReferenceSerializer typeRefSerializer
	@Inject IXtendJvmAssociations associations
	
	@Property val ProblemSupport problemSupport = new ProblemSupportImpl(this)
	@Property val TypeReferenceProvider typeReferenceProvider = new TypeReferenceProviderImpl(this)
	
	Map<EObject, Object> identityCache = newHashMap
	OwnedConverter typeRefConverter
	
	def getJvmAssociations() {
		return associations
	}
	
	def getTypeReferences() {
		typeReferences
	}
	
	def void setXtendFile(XtendFile xtendFile) {
		this._xtendFile = xtendFile
		this.typeRefConverter = new OwnedConverter(
			new StandardTypeReferenceOwner(services, xtendFile.eResource.resourceSet))
	}

	def private <IN extends EObject, OUT> OUT getOrCreate(IN in, (IN)=>OUT provider) {
		checkCanceled
		if (in == null)
			return null
		if (identityCache.containsKey(in))
			return identityCache.get(in) as OUT
		val result = provider.apply(in)
		identityCache.put(in, result)
		return result
	}

	def Visibility toVisibility(JvmVisibility delegate) {
		switch delegate {
			case JvmVisibility::DEFAULT: Visibility::DEFAULT
			case JvmVisibility::PRIVATE: Visibility::PRIVATE
			case JvmVisibility::PROTECTED: Visibility::PROTECTED
			case JvmVisibility::PUBLIC: Visibility::PUBLIC
		}
	}

	def Type toType(JvmType delegate) {
		getOrCreate(delegate) [
			switch delegate {
				JvmDeclaredType:
					toTypeDeclaration(delegate)
				JvmTypeParameter:
					toTypeParameterDeclaration(delegate)
				JvmVoid:
					new VoidTypeImpl => [
						it.delegate = delegate
						it.compilationUnit = this
					]
				JvmPrimitiveType:
					new PrimitiveTypeImpl => [
						it.delegate = delegate
						it.compilationUnit = this
					]
			}
		]}

	def MutableTypeDeclaration toTypeDeclaration(JvmDeclaredType delegate) {
		getOrCreate(delegate) [
			switch delegate {
				JvmGenericType case delegate.isInterface:
					null
				//					new InterfaceDeclarationJavaImpl => [
				//						it.delegate = delegate 
				//						it.compilationUnit = this
				//					]
				JvmGenericType:
					new JvmClassDeclarationImpl => [
						it.delegate = delegate
						it.compilationUnit = this
					]
				JvmAnnotationType:
					null //TODO
				JvmEnumerationType:
					null //TODO
			}
		]}

	def MutableTypeParameterDeclaration toTypeParameterDeclaration(JvmTypeParameter delegate) {
		getOrCreate(delegate) [
			new JvmTypeParameterDeclarationImpl => [
				it.delegate = delegate
				it.compilationUnit = this
			]
		]}

	def MutableParameterDeclaration toParameterDeclaration(JvmFormalParameter delegate) {
		getOrCreate(delegate) [
			new JvmParameterDeclarationImpl => [
				it.delegate = delegate
				it.compilationUnit = this
			]
		]}

	def MutableMemberDeclaration toMemberDeclaration(JvmMember delegate) {
		getOrCreate(delegate) [
			switch delegate {
				JvmDeclaredType:
					toTypeDeclaration(delegate)
				JvmOperation: 
					// TODO handle annotation properties	
					new JvmMethodDeclarationImpl => [
						it.delegate = delegate
						it.compilationUnit = this
					]
				JvmConstructor:
					new JvmConstructorDeclarationImpl => [
						it.delegate = delegate
						it.compilationUnit = this
					]
				JvmField:
					new JvmFieldDeclarationImpl => [
						it.delegate = delegate
						it.compilationUnit = this
					]
			//TODO JvmEnumerationLiteral
			}
		]}
	
	def MutableNamedElement toNamedElement(JvmIdentifiableElement delegate) {
		getOrCreate(delegate) [
			switch delegate {
				JvmMember : toMemberDeclaration(delegate)
				JvmTypeParameter : toTypeParameterDeclaration(delegate)
				JvmFormalParameter : toParameterDeclaration(delegate)
				default : throw new UnsupportedOperationException("Couldn't translate '"+delegate)
			}
		]
	}

	def TypeReference toTypeReference(JvmTypeReference delegate) {

		/*
		 * Nested JvmTypeReference's identity will not be preserved
		 * i.e. given 'List<String> myField' we will get the same TypeReference instance when asking
		 * the field for its type. But when asking for type arguments on that TypeReference we will 
		 * get a new instance representing 'String' each time.
		 */
		if (delegate == null)
			return null
		getOrCreate(delegate) [
			toTypeReference(typeRefConverter.toLightweightReference(delegate))
		]}

	def TypeReference toTypeReference(LightweightTypeReference delegate) {
		checkCanceled
		if (delegate == null)
			return null
		new TypeReferenceImpl => [
			it.delegate = delegate
			it.compilationUnit = this
		]
	}

	def XtendTypeDeclarationImpl<? extends XtendTypeDeclaration> toXtendTypeDeclaration(XtendTypeDeclaration delegate) {
		getOrCreate(delegate) [
			switch (delegate) {
				XtendClass:
					new XtendClassDeclarationImpl => [
						it.delegate = delegate
						it.compilationUnit = this
					]
			//TODO XtendAnnotationType 
			}
		]}

	def toXtendMemberDeclaration(XtendMember delegate) {
		getOrCreate(delegate) [
			switch (delegate) {
				XtendTypeDeclaration:
					toXtendTypeDeclaration(delegate)
				XtendFunction:
					new XtendMethodDeclarationImpl => [
						it.delegate = delegate
						it.compilationUnit = this
					]
				XtendConstructor:
					new XtendConstructorDeclarationImpl => [
						it.delegate = delegate
						it.compilationUnit = this
					]
				XtendField:
					new XtendFieldDeclarationImpl => [
						it.delegate = delegate
						it.compilationUnit = this
					]
			}
		]}

	def XtendParameterDeclarationImpl toXtendParameterDeclaration(XtendParameter delegate) {
		getOrCreate(delegate) [
			new XtendParameterDeclarationImpl => [
				it.delegate = delegate
				it.compilationUnit = this
			]
		]}

	def XtendTypeParameterDeclarationImpl toXtendTypeParameterDeclaration(JvmTypeParameter delegate) {
		getOrCreate(delegate) [
			new XtendTypeParameterDeclarationImpl => [
				it.delegate = delegate
				it.compilationUnit = this
			]
		]}
	
	def JvmTypeReference toJvmTypeReference(TypeReference typeRef) {
		checkCanceled
		return (typeRef as TypeReferenceImpl).lightWeightTypeReference.toJavaCompliantTypeReference
	}
	
	def void setCompilationStrategy(JvmExecutable executable, CompilationStrategy compilationStrategy) {
		checkCanceled
		typesBuilder.setBody(executable) [
			val context = new CompilationContextImpl(it, this, typeRefSerializer)
			it.append(compilationStrategy.compile(context))
		]
	}
	
}

class ProblemImpl implements Problem {
	
	String id
	String message
	Problem$Severity severity	
	
	new(String id,
	String message,
	Problem$Severity severity) {
		this.id = id
		this.message = message
		this.severity = severity
	}

	override getId() {
		return id
	}
	
	override getMessage() {
		return message
	}
	
	override getSeverity() {
		return severity
	}
	
}