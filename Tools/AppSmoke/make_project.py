#!/usr/bin/env python3
"""Generate isolated iPhone/Watch smoke apps around the production downloader."""
from pathlib import Path
import argparse
import plistlib

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('platform', choices=['watch', 'phone'])
platform = parser.parse_args().platform
watch = platform == 'watch'
name = 'DictionarySmoke'
directory = ROOT / 'build-smoke' / platform
project = directory / (name + '.xcodeproj')
project.mkdir(parents=True, exist_ok=True)
objects = {}

def add(key, isa, **fields):
    objects[key] = {'isa': isa, **fields}
    return key

sources = [ROOT / 'Tools/AppSmoke/SmokeApp.swift'] + [ROOT / 'Shared' / (name + '.swift') for name in
    ['DictionaryEntry', 'DictionaryText', 'DictionaryStore', 'DictionaryPack', 'DictionaryLibrary', 'DictionarySync', 'DictionaryDownloads', 'Localization']]
refs, builds = [], []
for i, path in enumerate(sources):
    ref = add(f'FILE{i:020d}', 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=str(path), sourceTree='<absolute>')
    refs.append(ref)
    builds.append(add(f'BUILD{i:019d}', 'PBXBuildFile', fileRef=ref))
catalog = add('CATALOG00000000000000000', 'PBXFileReference', lastKnownFileType='text.json', path=str(ROOT / 'Shared/Resources/DictionaryCatalog.json'), sourceTree='<absolute>')
catalog_build = add('CATBUILD0000000000000000', 'PBXBuildFile', fileRef=catalog)
product = add('PRODUCT00000000000000000', 'PBXFileReference', explicitFileType='wrapper.application', path=name + '.app', sourceTree='BUILT_PRODUCTS_DIR')
group = add('GROUP0000000000000000000', 'PBXGroup', children=refs+[catalog, product], sourceTree='<group>')
phase = add('SOURCES00000000000000000', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)
resources = add('RESOURCES000000000000000', 'PBXResourcesBuildPhase', buildActionMask=2147483647, files=[catalog_build], runOnlyForDeploymentPostprocessing=0)
frameworks = add('FRAMEWORKS00000000000000', 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
settings = {'SDKROOT': 'watchos' if watch else 'iphoneos',
    'WATCHOS_DEPLOYMENT_TARGET': '10.0', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0',
    'TARGETED_DEVICE_FAMILY': '4' if watch else '1',
    'SUPPORTED_PLATFORMS': 'watchos watchsimulator' if watch else 'iphoneos iphonesimulator',
    'PRODUCT_BUNDLE_IDENTIFIER': 'com.candyrect.instadict.smoke.' + platform,
    'PRODUCT_NAME': name, 'SWIFT_VERSION': '5.0', 'SWIFT_OPTIMIZATION_LEVEL': '-O',
    'GENERATE_INFOPLIST_FILE': 'YES', 'INFOPLIST_KEY_CFBundleDisplayName': 'Dict Smoke',
    'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES',
    'MARKETING_VERSION': '1.0', 'CURRENT_PROJECT_VERSION': '1', 'CODE_SIGNING_ALLOWED': 'NO',
    'OTHER_LDFLAGS': ['-lsqlite3', '-lz'], 'LD_RUNPATH_SEARCH_PATHS': ['$(inherited)', '@executable_path/Frameworks'],
    'CLANG_ENABLE_MODULES': 'YES'}
if watch:
    settings.update(INFOPLIST_KEY_WKApplication='YES', INFOPLIST_KEY_WKWatchOnly='YES')
targetconf = add('TARGETCONF00000000000000', 'XCBuildConfiguration', name='Release', buildSettings=settings)
targetlist = add('TARGETLIST00000000000000', 'XCConfigurationList', buildConfigurations=[targetconf], defaultConfigurationIsVisible=0, defaultConfigurationName='Release')
projconf = add('PROJCONF0000000000000000', 'XCBuildConfiguration', name='Release', buildSettings={})
projlist = add('PROJLIST0000000000000000', 'XCConfigurationList', buildConfigurations=[projconf], defaultConfigurationIsVisible=0, defaultConfigurationName='Release')
target = add('TARGET000000000000000000', 'PBXNativeTarget', name=name, productName=name, productType='com.apple.product-type.application', productReference=product, buildConfigurationList=targetlist, buildPhases=[phase, frameworks, resources], dependencies=[], buildRules=[])
proj = add('PROJECT00000000000000000', 'PBXProject', attributes={'LastUpgradeCheck': '2700'}, buildConfigurationList=projlist, compatibilityVersion='Xcode 14.0', developmentRegion='en', knownRegions=['en'], mainGroup=group, productRefGroup=group, projectDirPath='', projectRoot='', targets=[target])
with (project / 'project.pbxproj').open('wb') as output:
    plistlib.dump({'archiveVersion': '1', 'classes': {}, 'objectVersion': '56', 'objects': objects, 'rootObject': proj}, output)
print(project)
