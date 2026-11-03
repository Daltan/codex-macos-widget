#!/usr/bin/env python3
"""Dependency-free, deterministic Xcode project generation."""
import hashlib, json, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
objects = {}
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def add(object_key, **fields):
    key = ident(object_key); objects[key] = fields; return key
def render(value, depth=0):
    indent = '\t' * depth
    inner = '\t' * (depth + 1)
    if isinstance(value, dict):
        return '{\n' + ''.join(f'{inner}{json.dumps(k)} = {render(v, depth+1)};\n' for k,v in value.items()) + indent + '}'
    if isinstance(value, list):
        return '(\n' + ''.join(f'{inner}{render(v, depth+1)},\n' for v in value) + indent + ')'
    return json.dumps(str(value))
files = {}
for path in sorted((root/'Sources').rglob('*.swift')):
    relative = str(path.relative_to(root))
    files[relative] = add(relative, isa='PBXFileReference', lastKnownFileType='sourcecode.swift', path=relative, sourceTree='<group>')
app = add('app-product', isa='PBXFileReference', explicitFileType='wrapper.application', path='Codex Usage.app', sourceTree='BUILT_PRODUCTS_DIR')
widget = add('widget-product', isa='PBXFileReference', explicitFileType='wrapper.app-extension', path='CodexUsageWidget.appex', sourceTree='BUILT_PRODUCTS_DIR')
products = add('products', isa='PBXGroup', children=[app,widget], name='Products', sourceTree='<group>')
group = add('root', isa='PBXGroup', children=list(files.values())+[products], sourceTree='<group>')
def configs(name, settings):
    refs=[]
    for mode in ['Debug','Release']:
        config=dict(settings)
        config['SWIFT_OPTIMIZATION_LEVEL']='-Onone' if mode=='Debug' else '-O'
        config['DEBUG_INFORMATION_FORMAT']='dwarf' if mode=='Debug' else 'dwarf-with-dsym'
        refs.append(add(name+mode, isa='XCBuildConfiguration', buildSettings=config, name=mode))
    return add(name+'configs', isa='XCConfigurationList', buildConfigurations=refs, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')
common={'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CODE_SIGN_IDENTITY':'-','CODE_SIGN_STYLE':'Manual','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SWIFT_STRICT_CONCURRENCY':'complete','ARCHS':'$(ARCHS_STANDARD)','COPY_PHASE_STRIP':'NO'}
projectconfigs=configs('project',common)
targets=[]
for name, folder, product, bundle, product_type in [('CodexUsage','App',app,'com.daltan.codexusage','com.apple.product-type.application'),('CodexUsageWidget','Widget',widget,'com.daltan.codexusage.widget','com.apple.product-type.app-extension')]:
    sources=[]
    for path, ref in files.items():
        if '/Core/' in path or f'/{folder}/' in path:
            sources.append(add(name+path,isa='PBXBuildFile',fileRef=ref))
    phase=add(name+'sources',isa='PBXSourcesBuildPhase',buildActionMask=2147483647,files=sources,runOnlyForDeploymentPostprocessing=0)
    frameworks=add(name+'frameworks',isa='PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
    settings={'PRODUCT_NAME':'Codex Usage' if folder=='App' else name,'PRODUCT_BUNDLE_IDENTIFIER':bundle,'INFOPLIST_FILE':f'Config/{folder}-Info.plist','CODE_SIGN_ENTITLEMENTS':f'Config/{folder}.entitlements','GENERATE_INFOPLIST_FILE':'NO','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks'],'SWIFT_EMIT_LOC_STRINGS':'YES'}
    if folder=='Widget': settings.update({'APPLICATION_EXTENSION_API_ONLY':'YES','SKIP_INSTALL':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'$(inherited) WIDGET_EXTENSION'})
    phases=[phase,frameworks]; deps=[]
    if folder=='App':
        build=add('embed-widget-file',isa='PBXBuildFile',fileRef=widget,settings={'ATTRIBUTES':['RemoveHeadersOnCopy']})
        phases.append(add('embed-widget',isa='PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=13,files=[build],name='Embed App Extensions',runOnlyForDeploymentPostprocessing=0))
        proxy=add('widget-proxy',isa='PBXContainerItemProxy',containerPortal=ident('project'),proxyType=1,remoteGlobalIDString=ident('CodexUsageWidgettarget'),remoteInfo='CodexUsageWidget')
        deps.append(add('widget-dep',isa='PBXTargetDependency',target=ident('CodexUsageWidgettarget'),targetProxy=proxy))
    targets.append(add(name+'target',isa='PBXNativeTarget',buildConfigurationList=configs(name,settings),buildPhases=phases,buildRules=[],dependencies=deps,name=name,productName=name,productReference=product,productType=product_type))
add('project',isa='PBXProject',attributes={'LastUpgradeCheck':'2720','BuildIndependentTargetsInParallel':'YES'},buildConfigurationList=projectconfigs,compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['en','zh-Hans','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=targets)
project=root/'CodexUsage.xcodeproj'; project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+render({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':ident('project')})+'\n')
schemes=project/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
(schemes/'CodexUsage.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2720" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[0]}" BuildableName="Codex Usage.app" BlueprintName="CodexUsage" ReferencedContainer="container:CodexUsage.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{targets[0]}" BuildableName="Codex Usage.app" BlueprintName="CodexUsage" ReferencedContainer="container:CodexUsage.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated CodexUsage.xcodeproj')
