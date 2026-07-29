cmake_minimum_required(VERSION 3.14)

# 将上游 WebView 环境事件中的悬空异步回调替换为同步回退路径。
if(NOT DEFINED INPUT_FILE OR NOT EXISTS "${INPUT_FILE}")
  message(FATAL_ERROR "未找到 flutter_inappwebview_windows 源文件: ${INPUT_FILE}")
endif()
if(NOT DEFINED OUTPUT_FILE OR OUTPUT_FILE STREQUAL "")
  message(FATAL_ERROR "未指定 flutter_inappwebview_windows 补丁输出文件")
endif()

file(READ "${INPUT_FILE}" SOURCE_CONTENT)

set(UNSAFE_PROCESS_INFO_CALLBACK [=[                  if (auto environment13 = environment_.try_query<ICoreWebView2Environment13>()) {
                    auto hr = environment13->GetProcessExtendedInfos(Callback<ICoreWebView2GetProcessExtendedInfosCompletedHandler>(
                      [this](HRESULT error, wil::com_ptr<ICoreWebView2ProcessExtendedInfoCollection> processCollection) -> HRESULT
                      {
                        if (succeededOrLog(error) && processCollection) {
                          auto browserProcessInfosChangedDetail = BrowserProcessInfosChangedDetail::fromICoreWebView2ProcessExtendedInfoCollection(processCollection);
                          channelDelegate->onProcessInfosChanged(std::move(browserProcessInfosChangedDetail));
                        }
                        return S_OK;
                      }).Get());

                    if (succeededOrLog(hr)) {
                      return S_OK;
                    }
                  }
]=])

set(SAFE_PROCESS_INFO_CALLBACK [=[                  // 异步扩展信息回调会跨越 WebViewEnvironment 的生命周期并访问已释放通道。
                  // 使用同步进程信息接口，保证回调只在环境对象存活期间完成。
]=])

set(PATCH_FRAGMENT_COUNT 0)
set(PATCH_SEARCH_CONTENT "${SOURCE_CONTENT}")
string(LENGTH "${UNSAFE_PROCESS_INFO_CALLBACK}" PATCH_FRAGMENT_LENGTH)
while(TRUE)
  string(FIND
    "${PATCH_SEARCH_CONTENT}"
    "${UNSAFE_PROCESS_INFO_CALLBACK}"
    PATCH_FRAGMENT_POSITION)
  if(PATCH_FRAGMENT_POSITION EQUAL -1)
    break()
  endif()
  math(EXPR PATCH_FRAGMENT_COUNT "${PATCH_FRAGMENT_COUNT} + 1")
  math(EXPR PATCH_NEXT_POSITION
    "${PATCH_FRAGMENT_POSITION} + ${PATCH_FRAGMENT_LENGTH}")
  string(LENGTH "${PATCH_SEARCH_CONTENT}" PATCH_SEARCH_LENGTH)
  if(PATCH_NEXT_POSITION LESS PATCH_SEARCH_LENGTH)
    string(SUBSTRING
      "${PATCH_SEARCH_CONTENT}"
      ${PATCH_NEXT_POSITION}
      -1
      PATCH_SEARCH_CONTENT)
  else()
    set(PATCH_SEARCH_CONTENT "")
  endif()
endwhile()
if(NOT PATCH_FRAGMENT_COUNT EQUAL 1)
  message(FATAL_ERROR
    "WEBVIEW_PATCH_FRAGMENT_COUNT: 生命周期补丁片段必须恰好出现一次，实际 ${PATCH_FRAGMENT_COUNT} 次")
endif()

string(REPLACE
  "${UNSAFE_PROCESS_INFO_CALLBACK}"
  "${SAFE_PROCESS_INFO_CALLBACK}"
  PATCHED_SOURCE_CONTENT
  "${SOURCE_CONTENT}")
string(FIND
  "${PATCHED_SOURCE_CONTENT}"
  "${UNSAFE_PROCESS_INFO_CALLBACK}"
  REMAINING_CALLBACK_POSITION)
if(NOT REMAINING_CALLBACK_POSITION EQUAL -1)
  message(FATAL_ERROR
    "WEBVIEW_PATCH_REMAINS: flutter_inappwebview_windows 生命周期补丁未完整应用")
endif()

get_filename_component(OUTPUT_DIRECTORY "${OUTPUT_FILE}" DIRECTORY)
file(MAKE_DIRECTORY "${OUTPUT_DIRECTORY}")
file(WRITE "${OUTPUT_FILE}" "${PATCHED_SOURCE_CONTENT}")
