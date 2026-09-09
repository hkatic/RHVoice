// Copyright (C) 2026 RHVoice contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 2.1 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

#ifndef RHVOICE_MACOS_OS_LOGGER_HPP
#define RHVOICE_MACOS_OS_LOGGER_HPP

#include <os/log.h>
#include <string>

#include "core/event_logger.hpp"

namespace rhvoice_macos
{
  // Forwards the engine's diagnostics to the unified logging system:
  //   log stream --predicate 'subsystem == "org.rhvoice.RHVoice"' --level debug
  class OSLogger: public RHVoice::event_logger
  {
  public:
    OSLogger():
      handle(os_log_create("org.rhvoice.RHVoice","engine"))
    {
    }

    void log(const std::string& tag,RHVoice_log_level level,const std::string& message) const override
    {
      os_log_type_t type=OS_LOG_TYPE_DEFAULT;
      switch(level)
        {
        case RHVoice_log_level_trace:
        case RHVoice_log_level_debug:
          type=OS_LOG_TYPE_DEBUG;
          break;
        case RHVoice_log_level_info:
          type=OS_LOG_TYPE_INFO;
          break;
        case RHVoice_log_level_warning:
          type=OS_LOG_TYPE_DEFAULT;
          break;
        case RHVoice_log_level_error:
          type=OS_LOG_TYPE_ERROR;
          break;
        }
      os_log_with_type(handle,type,"[%{public}s] %{public}s",tag.c_str(),message.c_str());
    }

  private:
    os_log_t handle;
  };
}
#endif
