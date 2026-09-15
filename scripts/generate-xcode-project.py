#!/usr/bin/env python3
"""Generate the native Xcode app project using only Python's standard library.

App sources are file references; PodTrackCore is the local Swift package product.
Run again after adding, renaming, or removing app Swift files.
"""
from pathlib import Path
import hashlib
import plistlib

root = Path(__file__).resolve().parent.parent
project = root / 'PodTrack.xcodeproj'
project.mkdir(exist_ok=True)
def uid(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def quote(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

objects = []
def obj(key, body):
    objects.append(f'\t\t{uid(key)} = {{ {body} }};')
sources = sorted((root / 'Sources/PodTrack').rglob('*.swift'))
resources = sorted((root / 'Sources/PodTrack/Resources').glob('*.png'))
for path in sources:
    name = str(path.relative_to(root))
    obj('file:'+name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(name)}; sourceTree = SOURCE_ROOT;')
    obj('build:'+name, f'isa = PBXBuildFile; fileRef = {uid("file:"+name)};')
for path in resources:
    name = str(path.relative_to(root))
    obj('file:'+name, f'isa = PBXFileReference; lastKnownFileType = image.png; path = {quote(name)}; sourceTree = SOURCE_ROOT;')
    obj('build:'+name, f'isa = PBXBuildFile; fileRef = {uid("file:"+name)};')
obj('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PodTrack.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('source-group', 'isa = PBXGroup; name = App; sourceTree = "<group>"; children = (' + ', '.join(uid('file:'+str(p.relative_to(root))) for p in sources) + ');')
obj('resources-group', 'isa = PBXGroup; name = Resources; sourceTree = "<group>"; children = (' + ', '.join(uid('file:'+str(p.relative_to(root))) for p in resources) + ');')
obj('products-group', f'isa = PBXGroup; name = Products; sourceTree = "<group>"; children = ({uid("app-product")});')
obj('root-group', f'isa = PBXGroup; sourceTree = "<group>"; children = ({uid("source-group")}, {uid("resources-group")}, {uid("products-group")});')
obj('sources-phase', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; runOnlyForDeploymentPostprocessing = 0; files = (' + ', '.join(uid('build:'+str(p.relative_to(root))) for p in sources) + ');')
obj('local-package', 'isa = XCLocalSwiftPackageReference; relativePath = .;')
obj('core-product', f'isa = XCSwiftPackageProductDependency; package = {uid("local-package")}; productName = PodTrackCore;')
obj('core-link', f'isa = PBXBuildFile; productRef = {uid("core-product")};')
obj('frameworks-phase', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; runOnlyForDeploymentPostprocessing = 0; files = ({uid("core-link")});')
obj('resources-phase', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; runOnlyForDeploymentPostprocessing = 0; files = (' + ', '.join(uid('build:'+str(p.relative_to(root))) for p in resources) + ');')
metadata = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
for config in ['Debug','Release']:
    project_settings = 'MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0;'
    obj('project-'+config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ {project_settings} }};')
    settings = {
        'PRODUCT_NAME':'$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER':'dev.podtrack.mac',
        'INFOPLIST_FILE':'Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO',
        'CODE_SIGN_STYLE':'Automatic','CODE_SIGN_IDENTITY':'-',
        'ENABLE_HARDENED_RUNTIME':'YES','ENABLE_APP_SANDBOX':'NO',
        'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if config == 'Debug' else '-O',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if config == 'Debug' else '',
        'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks',
        'COMBINE_HIDPI_IMAGES':'YES','CURRENT_PROJECT_VERSION':metadata['CFBundleVersion'],'MARKETING_VERSION':metadata['CFBundleShortVersionString'],
        'ONLY_ACTIVE_ARCH':'YES' if config == 'Debug' else 'NO',
    }
    body = ' '.join(f'{key} = {quote(value)};' for key,value in settings.items())
    obj('target-'+config, f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ {body} }};')
for level in ['project','target']:
    obj(level+'-configs', f'isa = XCConfigurationList; buildConfigurations = ({uid(level+"-Debug")}, {uid(level+"-Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('app-target', f'isa = PBXNativeTarget; name = PodTrack; productName = PodTrack; productType = "com.apple.product-type.application"; productReference = {uid("app-product")}; buildConfigurationList = {uid("target-configs")}; buildPhases = ({uid("sources-phase")}, {uid("frameworks-phase")}, {uid("resources-phase")}); buildRules = (); dependencies = (); packageProductDependencies = ({uid("core-product")});')
obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {uid("project-configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {uid("root-group")}; productRefGroup = {uid("products-group")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("app-target")}); packageReferences = ({uid("local-package")});')
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'+'\n'.join(objects)+'\n\t};\n\trootObject = '+uid('project')+';\n}\n')
scheme_dir = project/'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True,exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("app-target")}" BuildableName="PodTrack.app" BlueprintName="PodTrack" ReferencedContainer="container:PodTrack.xcodeproj"/>'
(scheme_dir/'PodTrack.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f'Generated PodTrack.xcodeproj with {len(sources)} app source files.')
