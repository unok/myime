# Copyright 2024 AzooKey Project.
# All rights reserved.
#
# AzooKey conversion engine integration for Mozc.
{
  'targets': [
    {
      'target_name': 'azookey_immutable_converter',
      'type': 'static_library',
      'sources': [
        'azookey_immutable_converter.cc',
      ],
      'dependencies': [
        '<(mozc_oss_src_dir)/base/base.gyp:base',
        '<(mozc_oss_src_dir)/converter/converter_base.gyp:segments',
        '<(mozc_oss_src_dir)/request/request.gyp:conversion_request',
      ],
    },
  ],
}
