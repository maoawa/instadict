#!/usr/bin/env python3
"""Generate a standalone Watch benchmark target; excludes shipping app resources."""
from pathlib import Path
import plistlib

root=Path(__file__).resolve().parent
project=root/'WatchBenchmark.xcodeproj'
project.mkdir(exist_ok=True)
objects={}
def add(identifier,isa,**fields):
    objects[identifier]={'isa':isa,**fields}
    return identifier

sources=['WatchBenchmark/BenchmarkApp.swift','WatchBenchmark/BenchmarkStore.swift','WatchBenchmark/LookupBenchmark.swift',
         '../Shared/DictionaryEntry.swift','../Shared/DictionaryStore.swift','../Shared/DictionaryText.swift']
refs=[];builds=[]
for index,path in enumerate(sources):
    ref=add(f'FILE{index:020d}','PBXFileReference',lastKnownFileType='sourcecode.swift',path=path,sourceTree='<group>')
    refs.append(ref)
    builds.append(add(f'BUILD{index:019d}','PBXBuildFile',fileRef=ref))
product=add('PRODUCT00000000000000000','PBXFileReference',explicitFileType='wrapper.application',path='WatchBenchmark.app',sourceTree='BUILT_PRODUCTS_DIR')
group=add('GROUP0000000000000000000','PBXGroup',children=refs+[product],sourceTree='<group>')
phase=add('SOURCES00000000000000000','PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0)
frameworks=add('FRAMEWORKS00000000000000','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
resources=add('RESOURCES000000000000000','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
settings={'SDKROOT':'watchos','WATCHOS_DEPLOYMENT_TARGET':'10.0','TARGETED_DEVICE_FAMILY':'4',
    'SUPPORTED_PLATFORMS':'watchos watchsimulator','PRODUCT_BUNDLE_IDENTIFIER':'com.candyrect.instadict.benchmark',
    'PRODUCT_NAME':'$(TARGET_NAME)','SWIFT_VERSION':'6.0','SWIFT_OPTIMIZATION_LEVEL':'-O','SWIFT_COMPILATION_MODE':'wholemodule',
    'GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_KEY_CFBundleDisplayName':'Dict Benchmark',
    'INFOPLIST_KEY_WKApplication':'YES','INFOPLIST_KEY_WKWatchOnly':'YES',
    'MARKETING_VERSION':'1.0','CURRENT_PROJECT_VERSION':'1','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'CVS7CJXPF7',
    'OTHER_LDFLAGS':['-lsqlite3','-lz'],'LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],
    'SWIFT_STRICT_CONCURRENCY':'complete','CLANG_ENABLE_MODULES':'YES','DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym'}
targetconf=add('TARGETCONF00000000000000','XCBuildConfiguration',name='Release',buildSettings=settings)
targetlist=add('TARGETLIST00000000000000','XCConfigurationList',buildConfigurations=[targetconf],defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
projconf=add('PROJCONF0000000000000000','XCBuildConfiguration',name='Release',buildSettings={})
projlist=add('PROJLIST0000000000000000','XCConfigurationList',buildConfigurations=[projconf],defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
target=add('TARGET000000000000000000','PBXNativeTarget',name='WatchBenchmark',productName='WatchBenchmark',productType='com.apple.product-type.application',productReference=product,buildConfigurationList=targetlist,buildPhases=[phase,frameworks,resources],dependencies=[],buildRules=[])
proj=add('PROJECT00000000000000000','PBXProject',attributes={'LastUpgradeCheck':'2700'},buildConfigurationList=projlist,compatibilityVersion='Xcode 14.0',developmentRegion='en',knownRegions=['en','Base'],mainGroup=group,productRefGroup=group,projectDirPath='',projectRoot='',targets=[target])
with (project/'project.pbxproj').open('wb') as f:
    plistlib.dump({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':proj},f,sort_keys=False)
schemes=project/'xcshareddata'/'xcschemes';schemes.mkdir(parents=True,exist_ok=True)
(schemes/'WatchBenchmark.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="WatchBenchmark.app" BlueprintName="WatchBenchmark" ReferencedContainer="container:WatchBenchmark.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Release" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="WatchBenchmark.app" BlueprintName="WatchBenchmark" ReferencedContainer="container:WatchBenchmark.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Release"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>
''')
print(project)
