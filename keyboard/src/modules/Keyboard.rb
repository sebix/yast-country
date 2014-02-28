# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2012 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------

# File:
#   Keyboard.ycp
#
# Module:
#   Keyboard
#
# Summary:
#   Provide information regarding the keyboard.
#
# Authors:
#   Thomas Roelz <tom@suse.de>
#
# Maintainer:	Jiri Suchomel <jsuchome@suse.cz>
#
# $Id$
#
# Usage:
# ------
# This module provides the following data for public access via Keyboard::<var-name>.
#
#      !!! These are to be used READ_ONLY !!!
#
# Set in the constructor after the first import (only after probing):
#
#	kb_model
#	XkbLayout
#	unique_key
#
# Set after having called SetKeyboard( keyboard ).
#
#	XkbModel
#	XkbVariant
#	XkbOptions
#	LeftAlt
#	RightAlt
#	ScrollLock
#	RightCtl
#	Apply
#	keymap
#	compose_table
#	current_kbd
#	ckb_cmd
#	xkb_cmd
#
#
# This module provides the following functions for public access via Keyboard::<func-name>(...)
#
#	Keyboard()			- Module constructor.
#			  		  If saved module data exists in continue mode, these are read in.
#			 		  Otherwise Hardware is probed.
#
#	MakeProposal()			- return user-readable description of keyboard
#
#	Probe()				- Force new hardware probing and set public data accordingly.
#
#	Save()				- Save module data to /var/lib/YaST2/Keyboard_data.ycp
#
#	Restore()			- Load module data from /var/lib/YaST2/Keyboard_data.ycp
#
#	SetKeyboard()			- Set public data to values corresponding to the given language.
#
#	GetKeyboardForLanguage()	- Get the keyboard language for a given language code.
#
# 	Set()				- Set the keyboard to the given keyboard language.
# 	SetConsole()			- Set the console keyboard to the given keyboard language.
#
# 	SetX11()			- Set the X11 keyboard to the given keyboard language.
#
#	Selection()			- Get map of translated keyboards to be displayed in the GUI.
#
require "yast"

module Yast
  class KeyboardClass < Module
    def main
      Yast.import "UI"
      textdomain "country"

      Yast.import "Arch"
      Yast.import "AsciiFile"
      Yast.import "Directory"
      Yast.import "FileUtils"
      Yast.import "Label"
      Yast.import "Language"
      Yast.import "Linuxrc"
      Yast.import "Misc"
      Yast.import "Mode"
      Yast.import "Package"
      Yast.import "ProductFeatures"
      Yast.import "Stage"
      Yast.import "XVersion"

      # ------------------------------------------------------------------------
      # START: Globally defined data to be accessed via Keyboard::<variable>
      # ------------------------------------------------------------------------

      # kb_model string
      #
      @kb_model = "pc104"

      # XkbModel string
      #
      @XkbModel = ""

      # XkbLayout string
      # Only some keyboards do report this information (e.g. sparc).
      #
      @XkbLayout = ""

      # XkbVariant string
      #
      @XkbVariant = ""

      # keymap string for ncurses
      #
      @keymap = "us.map.gz"

      # compose_table entry
      #
      @compose_table = "clear winkeys shiftctrl latin1.add"

      # X11 Options string
      #
      @XkbOptions = ""

      # X11 LeftAlt
      #
      @LeftAlt = ""

      # X11 RightAlt
      #
      @RightAlt = ""

      # X11 RightCtl
      #
      @RightCtl = ""

      # X11 ScrollLock
      #
      @ScrollLock = ""

      # Apply string fuer xbcmd
      #
      @Apply = ""

      # The console keyboard command
      #
      @ckb_cmd = ""

      # The X11 keyboard command
      #
      @xkb_cmd = ""

      # The keyboard currently set.
      #
      @current_kbd = ""

      # keyboard set on start
      @keyboard_on_entry = ""

      # expert values on start
      @expert_on_entry = {}

      # The default keyboard if set.
      #
      @default_kbd = ""

      # Flag indicating if the user has chosen a keyboard.
      # To be set from outside.
      #
      @user_decision = false

      # unique key
      #
      @unique_key = ""

      # state of Expert settings
      @ExpertSettingsChanged = false

      # --------------------------------------------------------------
      # END: Globally defined data to be accessed via Keyboard::<variable>
      # --------------------------------------------------------------


      # --------------------------------------------------------------
      # START: Locally defined data
      # --------------------------------------------------------------

      # if Keyboard::Restore() was called
      @restore_called = false

      # User readable description, access via Keyboard::MakeProposal()
      #
      @name = ""

      # Keyboard description from DB
      #
      @kbd_descr = []

      @kbd_rate = ""
      @kbd_delay = ""
      @kbd_numlock = ""
      @kbd_disable_capslock = ""

      @keyboardprobelist = [] # List of all probed keyboards

      # running in XEN?
      @xen_is_running = nil
      Keyboard()
    end

    # ------------------------------------------------------------------
    # START: Globally defined functions
    # ------------------------------------------------------------------

    # GetKbdSysconfig()
    #
    # Restore the the non-keyboard values from sysconfig.

    def GetKbdSysconfig
      # Read the the variables not touched by the module to be able to
      # store them again on Save().
      #

      if FileUtils.Exists("/etc/vconsole.conf")

        @kbd_rate = Misc.SysconfigRead(
          path(".etc.vconsole_conf.KBD_RATE"),
          @kbd_rate
        )
        @kbd_delay = Misc.SysconfigRead(
          path(".etc.vconsole_conf.KBD_DELAY"),
          @kbd_delay
        )
        @kbd_numlock = Misc.SysconfigRead(
          path(".etc.vconsole_conf.KBD_NUMLOCK"),
          @kbd_numlock
        )
        @kbd_disable_capslock = Misc.SysconfigRead(
          path(".etc.vconsole_conf.KBD_DISABLE_CAPS_LOCK"),
          @kbd_disable_capslock
        )
      end

      Builtins.y2milestone(
        "rate:%1 delay:%2 numlock:%3 disclock:%4",
        @kbd_rate,
        @kbd_delay,
        @kbd_numlock,
        @kbd_disable_capslock
      )

      nil
    end

    # get_reduced_keyboard_db()
    #
    # Read the Keyboard DB and select entries for current XkbModel and architecture.
    #
    # @return  Reduced keyboard DB (map)

    def get_reduced_keyboard_db
      # The keyboard DB is a very big map containing entries for all known keyboard
      # languages. Each of these entries contains a map of the different known
      # architectures and each of these architectures contains a map for the different
      # kb_models possible on the given architecture. This innermost map finally contains
      # data relevant for ncurses.
      #
      # $[
      #    "english-us":
      #     [
      #	  ...language stuff...
      #	  $[   "i386" :
      #	       $[ "pc104":
      #	          $[   "ncurses": "us.map.gz" ]],
      #
      # What now follows is code that cuts out from this map the unnecessary
      # architectures and XkbModels. The different languages are kept.
      #
      # Load the keyboard DB.
      # Do not hold this database in a permanent module variable (it's very large).

      # eval is necessary for translating the texts needed to be translated
      all_keyboards = Convert.convert(
        Builtins.eval(SCR.Read(path(".target.yast2"), "keyboard_raw.ycp")),
        :from => "any",
        :to   => "map <string, list>"
      )

      all_keyboards = {} if all_keyboards == nil

      # The new reduced map of keyboard data.
      #
      keyboards = {}
      Builtins.y2milestone("keyboard model used: %1", @kb_model)
      # loop over all languages
      Builtins.foreach(all_keyboards) do |kb_lang, description|
        if Builtins.size(description) == 2
          # Get the data for the current kb_model
          #
          keyboard_model = Ops.get_map(description, [1, @kb_model], {})

          if Ops.greater_than(Builtins.size(keyboard_model), 0) # found an entry
            # Add the data found (as list) to the new map under the current
            # language key.
            #
            keyboard_selected = [] # temporary list

            # Add the language stuff.
            #
            keyboard_selected = Builtins.add(
              keyboard_selected,
              Ops.get_string(description, 0, "")
            )

            # Add the Qt- and ncurses-data.
            #
            keyboard_selected = Builtins.add(keyboard_selected, keyboard_model)

            # Add this list to the reduced keyboard map under the current language key.
            #
            Ops.set(keyboards, kb_lang, keyboard_selected)
          end
        end
      end

      deep_copy(keyboards)
    end # get_reduced_keyboard_db()

    # Return a map for conversion from keymap to YaST2 keyboard code()
    # Get the map of translated keyboard names.
    # @param   -
    # @return  [Hash] of $[ keyboard_code : keyboard_name, ...] for all known
    #      keyboards. 'keyboard_code' is used internally in Set and Get
    #      functions. 'keyboard_name' is a user-readable string.
    #      Uses Language::language for translation.
    #
    def keymap2yast
      Builtins.mapmap(get_reduced_keyboard_db) do |code, kbd_value|
        code_map = Ops.get_map(kbd_value, 1, {})
        codel = Builtins.splitstring(
          Ops.get_string(code_map, "ncurses", ""),
          "."
        )
        { Ops.get_string(codel, 0, "") => code }
      end
    end

    # GetX11KeyData()
    #
    # Get the keyboard info for X11 for the given keymap
    #
    # @param	name of the keymap
    #
    # @return  [Hash] containing the x11 config data
    #
    def GetX11KeyData(keymap)
      cmd = "/usr/sbin/xkbctrl"
      x11data = {}

      if Ops.greater_than(SCR.Read(path(".target.size"), cmd), 0)
        file = Ops.add(Directory.tmpdir, "/xkbctrl.out")
        cmd = Ops.add(Ops.add(cmd, " "), keymap)
        SCR.Execute(path(".target.bash"), Ops.add(Ops.add(cmd, " > "), file))
        x11data = Convert.to_map(SCR.Read(path(".target.ycp"), file))
      else
        Builtins.y2warning("/usr/sbin/xkbctrl not found")
      end
      deep_copy(x11data)
    end

    # Return human readable (and translated) name of the given keyboard map
    # @param [String] kbd keyboard map
    # @return [String]
    def GetKeyboardName(kbd)
      keyboards = get_reduced_keyboard_db
      descr = Ops.get_list(keyboards, kbd, [])
      ret = kbd

      if descr != []
        translate = Ops.get_string(descr, 0, kbd)
        ret = Builtins.eval(translate)
      end
      ret
    end

    # GetExpertValues()
    #
    # Return the values for the various expert settings in a map
    #
    # @return  [Hash] with values filled in
    #
    def GetExpertValues
      ret = {
        "rate"     => @kbd_rate,
        "delay"    => @kbd_delay,
        "numlock"  => @kbd_numlock,
        "discaps"  => @kbd_disable_capslock == "yes" ? true : false
      }
      deep_copy(ret)
    end

    # Get the system_language --> keyboard_language conversion map.
    #
    # @return  conversion map
    #
    # @see #get_xkblayout2keyboard()

    def get_lang2keyboard
      base_lang2keyboard = Convert.to_map(
        SCR.Read(path(".target.yast2"), "lang2keyboard.ycp")
      )
      base_lang2keyboard = {} if base_lang2keyboard == nil

      Builtins.union(base_lang2keyboard, Language.GetLang2KeyboardMap(true))
    end




    # GetKeyboardForLanguage()
    #
    # Get the keyboard language for the given system language.
    #
    # @param	System language code, e.g. "en_US".
    #		Default keyboard language to be returned if nothing found.
    #
    # @return  The keyboard language for this language, e.g. "english-us"
    #		or the default value if nothing found.
    #
    def GetKeyboardForLanguage(sys_language, default_keyboard)
      lang2keyboard = get_lang2keyboard
      kb = Ops.get_string(lang2keyboard, sys_language, "")

      if kb == ""
        sys_language = Builtins.substring(sys_language, 0, 2)
        kb = Ops.get_string(lang2keyboard, sys_language, default_keyboard)
      end
      Builtins.y2milestone(
        "GetKeyboardForLanguage lang:%1 def:%2 ret:%3",
        sys_language,
        default_keyboard,
        kb
      )
      kb
    end

    # check if we are running in XEN (autorepeat functionality not supported)
    # seem bnc#376945, #371756
    def xen_running
      if @xen_is_running == nil
        @xen_is_running = Convert.to_boolean(SCR.Read(path(".probe.xen")))
      end
      @xen_is_running == true
    end


    # run X11 configuration after inital boot
    def x11_setup_needed
      Arch.x11_setup_needed &&
        !(Linuxrc.serial_console || Linuxrc.vnc || Linuxrc.usessh ||
          Linuxrc.text)
    end

    # SetKeyboard()
    #
    # Set language specific module data to reflect the given keyboard layout.
    #
    # @param	Keyboard layout e.g.  "english-us"
    #
    # @return  true	- Success. Language set in public data.
    #		false	- Error. Language not set.
    #

    def SetKeyboard(keyboard)
      Builtins.y2milestone("Setting keyboard to: <%1>", keyboard)

      # Get the reduced keyboard DB.
      #
      keyboards = get_reduced_keyboard_db

      Builtins.y2debug("reduced kbd db %1", keyboards)
      # Get the entry from the reduced local map for the given language.
      #
      @kbd_descr = Ops.get_list(keyboards, keyboard, [])

      Builtins.y2milestone(
        "Description for keyboard <%1>: <%2>",
        keyboard,
        @kbd_descr
      )

      if @kbd_descr != [] # keyboard found
        # Get keymap for ncurses
        #
        @keymap = Ops.get_string(@kbd_descr, [1, "ncurses"], "us.map.gz")
        translate = Ops.get_string(@kbd_descr, 0, keyboard)
        @name = Builtins.eval(translate)

        x11data = GetX11KeyData(@keymap)
        Builtins.y2milestone("x11data=%1", x11data)

        @XkbModel = Ops.get_string(x11data, "XkbModel", "pc104")
        @XkbLayout = Ops.get_string(x11data, "XkbLayout", "")
        @XkbVariant = Ops.get_string(x11data, "XkbVariant", "basic")
        @XkbOptions = Ops.get_string(x11data, "XkbOptions", "")
        @LeftAlt = Ops.get_string(x11data, "LeftAlt", "")
        @RightAlt = Ops.get_string(x11data, "RightAlt", "")
        @ScrollLock = Ops.get_string(x11data, "ScrollLock", "")
        @RightCtl = Ops.get_string(x11data, "RightCtl", "")
        @Apply = Ops.get_string(x11data, "Apply", "")

        # Build the compose table entry.
        #
        @compose_table = "clear "

        if @XkbModel == "pc104" || @XkbModel == "pc105"
          @compose_table = Ops.add(@compose_table, "winkeys shiftctrl ")
        end

        # Check for "compose" entry in keytable, might define
        # a different encoding (i.e. "latin2").
        #
        compose = Ops.get_string(@kbd_descr, [1, "compose"], "latin1.add")

        @compose_table = Ops.add(@compose_table, compose) # Language not found.
      else
        return false # Error
      end

      # Console command...
      @ckb_cmd = Ops.add("/bin/loadkeys ", @keymap)

      # X11 command...
      # do not try to run this with remote X display
      if Ops.greater_than(Builtins.size(@Apply), 0) && x11_setup_needed
        @xkb_cmd = Ops.add(Ops.add(XVersion.binPath, "/setxkbmap "), @Apply)
      else
        @xkb_cmd = ""
      end

      # Store keyboard just set.
      #
      @current_kbd = keyboard

      # On first assignment store default keyboard.
      #
      @default_kbd = @current_kbd if @default_kbd == "" # not yet assigned

      true # OK
    end # SetKeyboard()


    # Restore the the data from sysconfig.
    #
    # @return  true	- Data could be restored
    #		false	- Restore not successful
    #
    # @see #Save()
    def Restore
      ret = false
      @restore_called = true
      GetKbdSysconfig()

      if !Stage.initial || Mode.live_installation
        # Read YaST2 keyboard var.
        #
        @current_kbd = Misc.SysconfigRead(
          path(".sysconfig.keyboard.YAST_KEYBOARD"),
          ""
        )
        pos = Builtins.find(@current_kbd, ",")
        if pos != nil && Ops.greater_than(pos, 0)
          @kb_model = Builtins.substring(@current_kbd, Ops.add(pos, 1))
          @current_kbd = Builtins.substring(@current_kbd, 0, pos)
        end

        Builtins.y2milestone("current_kbd %1 model %2", @current_kbd, @kb_model)
        if @current_kbd == ""
          Builtins.y2milestone("Restoring data failed, returning defaults")
          @current_kbd = "english-us"
          @kb_model = "pc104"
          ret = false
        else
          if !Mode.config
            # Restore module data.
            #
            SetKeyboard(@current_kbd)
            Builtins.y2milestone(
              "Restored data (sysconfig) for keyboard: <%1>",
              @current_kbd
            )
          else
            # for cloning, to be shown in Summary
            @name = GetKeyboardName(@current_kbd)
          end
          ret = true
        end
      else
        ret = true
      end
      ret
    end # Restore()

    # get_xkblayout2keyboard()
    #
    # Get the xkblayout --> keyboard_language conversion map.
    #
    # @return  conversion map
    #
    # @see	get_lang2keyboard()

    def get_xkblayout2keyboard
      # The xkblayout --> keyboard_language conversion map.
      #
      xkblayout2keyboard = Convert.to_map(
        SCR.Read(path(".target.yast2"), "xkblayout2keyboard.ycp")
      )

      xkblayout2keyboard = {} if xkblayout2keyboard == nil

      deep_copy(xkblayout2keyboard)
    end # get_xkblayout2keyboard()


    # XkblayoutToKeyboard()
    #
    # Convert X11 keyboard layout name to yast2 name for keyboard description.
    # e.g. "de" --> "german"
    #
    # @param [String] x11_layout
    #
    # @return         [String]  yast2 name for keyboard description

    def XkblayoutToKeyboard(x11_layout)
      xkblayout2keyboard = get_xkblayout2keyboard

      # Now get the YaST2 internal representation of this keyboard layout.
      #
      ret = Ops.get_string(xkblayout2keyboard, x11_layout, "")
      Builtins.y2milestone(
        " XkblayoutToKeyboard x11:%1 ret:%2",
        x11_layout,
        ret
      )
      ret
    end

    # Probe keyboard and set local module data.

    def probe_settings
      # First assign the kb_model. This is e.g. "pc104".
      # Aside from being used directly for writing the XF86Config file this is later on
      # used to search the YaST2 keyboards database (it's a key in a map).

      # Probe the keyboard.
      #
      if !Mode.config
        @keyboardprobelist = Convert.to_list(SCR.Read(path(".probe.keyboard")))

        Builtins.y2milestone("Probed keyboard: <%1>", @keyboardprobelist)

        # Get the first keyboard from the list (it should exist).
        #
        keyboardmap1 = Ops.get_map(@keyboardprobelist, 0, {})

        # Get the unique_key
        #
        @unique_key = Ops.get_string(keyboardmap1, "unique_key", "")

        # Get the keyboard data for this first keyboard.
        #
        keyboardmap2 = Ops.get_map(keyboardmap1, ["keyboard", 0], {})

        # Assign the XkbModel.
        #
        @kb_model = Ops.get_string(keyboardmap2, "xkbmodel", "pc104")

        Builtins.y2milestone("kb_model: <%1>", @kb_model)

        # Assign the XkbLayout.
        # Only some keyboards do report this information (e.g. sparc).
        #
        @XkbLayout = Ops.get_string(keyboardmap2, "xkblayout", "")

        Builtins.y2milestone("Xkblayout: <%1>", @XkbLayout)
      else
        @kb_model = "pc104"
      end

      nil
    end # probe_settings()

    # Probe()
    #
    # Allow for intentional probing by applications.
    #
    # @see #Keyboard()
    def Probe
      Builtins.y2milestone("Keyboard::Probe")
      probe_settings

      # Set the module to the current system language to achieve a consistent
      # state. This may be superfluous because a client may do it also but
      # just in case...
      #
      default_keyboard = ""

      # Some keyboards (i.e. sparc) report their layout, try to use this information here
      #
      if @XkbLayout != "" # we do have hardware info
        default_keyboard = GetKeyboardForLanguage(@XkbLayout, default_keyboard) # no hardware info ==> select default keyboard dependent on system language
      else
        default_keyboard = GetKeyboardForLanguage(
          Language.language,
          "english-us"
        )
      end

      # Set the module state.
      #
      SetKeyboard(default_keyboard)

      if Stage.initial
        keytable = Linuxrc.InstallInf("Keytable")
        # set the keyboard from linuxrc
        if keytable != nil
          Builtins.y2milestone("linuxrc keyboard: %1", keytable)
          map2yast = Builtins.union(
            keymap2yast,
            { "dk" => "danish", "de-lat1-nd" => "german" }
          )
          if Builtins.issubstring(keytable, ".map.gz")
            keytable = Builtins.substring(
              keytable,
              0,
              Builtins.find(keytable, ".map.gz")
            )
          end
          if Ops.get_string(map2yast, keytable, "") != ""
            Set(Ops.get_string(map2yast, keytable, ""))
            # do not reset it in proposal
            @user_decision = true
          end
        # set keyboard now (before proposal - see bug #113664)
        elsif Language.preselected != "en_US"
          Builtins.y2milestone(
            "language (%1) was preselected -> setting keyboard to %2",
            Language.preselected,
            default_keyboard
          )
          Set(default_keyboard)
        end
      end
      Builtins.y2milestone("End Probe %1", default_keyboard)

      nil
    end # Probe()


    # Keyboard()
    #
    # The module constructor.
    # Sets the proprietary module data defined globally for public access.
    # This is done only once (and automatically) when the module is loaded for the first time.
    #
    # @see #Probe()
    def Keyboard
      return if Mode.config

      # We have these possible sources of information:
      #
      # probed data:	- installation initial mode --> probing
      # sysconfig:	- installation continue mode or normal mode
      #
      Builtins.y2milestone("initial :%1, update:%2", Stage.initial, Mode.update)

      success = false

      # If not in initial mode try to restore from sysconfig.
      if !Stage.initial || Mode.live_installation
        success = Restore()
      else
        GetKbdSysconfig()
      end

      # In initial mode or if restoring failed do probe.
      if !success
        # On module entry probe the hardware and set all those data
        # needed for public access.
        Probe()
      end

      nil
    end # Keyboard()

    # Just store inital values - read was done in constructor
    def Read
      @keyboard_on_entry = @current_kbd
      @expert_on_entry = GetExpertValues()
      @ExpertSettingsChanged = false
      Builtins.y2debug("keyboard_on_entry: %1", @keyboard_on_entry)
      true
    end

    # was anything modified?
    def Modified
      @current_kbd != @keyboard_on_entry || @ExpertSettingsChanged
    end


    # Save the current data into a file to be read after a reboot.
    #
    def Save
      if Mode.update
        kbd = Misc.SysconfigRead(path(".sysconfig.keyboard.YAST_KEYBOARD"), "")
        if kbd.empty?
          kmap = Misc.SysconfigRead(path(".etc.vconsole_conf.KEYMAP"), "")
          # if still nothing found, lets check the obsolete config option:
          kmap = Misc.SysconfigRead(path(".sysconfig.keyboard.KEYTABLE"), "") if kmap.empty?
          if !kmap.empty?
            data = GetX11KeyData(kmap)
            if (data["XkbLayout"] || "").size > 0
              kbd = XkblayoutToKeyboard(data["XkbLayout"]) + "," + (data["XkbModel"] || "pc104")
              SCR.Write(path(".sysconfig.keyboard.YAST_KEYBOARD"), kbd)
              SCR.Write(
                path(".sysconfig.keyboard.YAST_KEYBOARD.comment"),
                "\n" +
                  "# The YaST-internal identifier of the attached keyboard.\n" +
                  "#\n"
              )
              SCR.Write(path(".sysconfig.keyboard"), nil) # flush
            end
          end
        end
        return
      end

      # Write some sysconfig variables.
      # Set keytable, compose_table and tty list.
      #
      SCR.Write(
        path(".sysconfig.keyboard.YAST_KEYBOARD"),
        Ops.add(Ops.add(@current_kbd, ","), @kb_model)
      )
      SCR.Write(
        path(".sysconfig.keyboard.YAST_KEYBOARD.comment"),
        "\n" +
          "# The YaST-internal identifier of the attached keyboard.\n" +
          "#\n"
      )
      SCR.Write(path(".sysconfig.keyboard"), nil) # flush

      SCR.Write(path(".etc.vconsole_conf.KEYMAP"), @keymap.gsub(/(.*)\.map\.gz/, '\1'))
      SCR.Write(path(".etc.vconsole_conf.COMPOSETABLE"), @compose_table)
      SCR.Write(path(".etc.vconsole_conf.KBD_RATE"), @kbd_rate)
      SCR.Write(path(".etc.vconsole_conf.KBD_DELAY"), @kbd_delay)
      SCR.Write(path(".etc.vconsole_conf.KBD_NUMLOCK"), @kbd_numlock)
      SCR.Write(
        path(".etc.vconsole_conf.KBD_DISABLE_CAPS_LOCK"),
        @kbd_disable_capslock
      )
      SCR.Write(path(".etc.vconsole_conf"), nil) # flush

      # As a preliminary step mark all keyboards except the one to be configured
      # as configured = no and needed = no. Afterwards this one keyboard will be
      # marked as configured = yes and needed = yes. This has to be done  to
      # prevent any problems that may occur if the user plugs in and out different
      # keyboards or if a keyboard is selected from the database despite the fact
      # that a keyboard has been probed. Otherwise the config popup may nag the user
      # again and again.
      #
      # In order to get a list of *ALL* keyboards that have ever been conected to
      # the system we must do a *manual* probing (accessing the libhd database).
      # Doing only a "normal" probing would deliver only the *currently* attached
      # keyboards which in turn would not allow to "unmark" all keyboards that may
      # have been removed.
      #
      # Do *NOT* use probe_settings() here because this would newly assign the global
      # "unique_key" which is not what we want here. It may have been cleared
      # intentionally due to the users selection of a keyboard from the YaST database.
      # Furthermore this would assign a unique_key even if there is no keyboard attached
      # (if there _was_ a keyboard attached).
      #
      # Manual probing
      @keyboardprobelist = Convert.to_list(
        SCR.Read(path(".probe.keyboard.manual"))
      )

      list_size = Builtins.size(@keyboardprobelist)

      if Ops.greater_than(list_size, 0)
        i = 0

        while Ops.less_than(i, list_size)
          current_keyboard = Ops.get_map(@keyboardprobelist, i, {})
          current_key = Ops.get_string(current_keyboard, "unique_key", "")

          if current_key != ""
            # OK, there is a key to mark...
            #
            if current_key != @unique_key
              # OK, this key is _not_ the key of the keyboard to be configured.
              # If the user selected a keyboard from the database Keyboard::unique_key
              # has been set to "" there which also applies here.
              # ==> Mark with "no".
              #
              SCR.Write(path(".probe.status.configured"), current_key, :no)
              Builtins.y2milestone(
                "Marked keyboard <%1> as configured = no",
                current_key
              )

              SCR.Write(path(".probe.status.needed"), current_key, :no)
              Builtins.y2milestone(
                "Marked keyboard <%1> as needed = no",
                current_key
              )
            else
              Builtins.y2milestone(
                "Skipping active key <%1> --> to be configured",
                current_key
              )
            end
          end

          i = Ops.add(i, 1) # next keyboard
        end
      else
        Builtins.y2milestone(
          "No probed keyboards. Not unconfiguring any keyboards"
        )
      end

      # Only if the keyboard has been probed in this run the unique_key
      # is not empty. Only in this case mark the device as "configured".
      # In any other case the device should already be configured and
      # the marking can't be done because the unique_key is missing.
      # ==> Only mark after probing!
      #
      if @unique_key != ""
        SCR.Write(path(".probe.status.configured"), @unique_key, :yes)
        Builtins.y2milestone("Marked keyboard <%1> as configured", @unique_key)

        if !Linuxrc.serial_console
          SCR.Write(path(".probe.status.needed"), @unique_key, :yes)
          Builtins.y2milestone("Marked keyboard <%1> as needed", @unique_key)
        end
      else
        Builtins.y2milestone(
          "NOT marking keyboard as configured (no unique_key)"
        )
      end

      Builtins.y2milestone("Saved data for keyboard: <%1>", @current_kbd)

      nil
    end # Save()


    # Name()
    # Just return the keyboard name, without setting anything.
    # @return [String] user readable description.

    def Name
      @name
    end

    # Set the console keyboard to the given keyboard language.
    #
    # @param	Keyboard language e.g.  "english-us"
    #
    # @return  The loadkeys command that has been executed to do it.
    #		(also stored in Keyboard::ckb_cmd)
    def SetConsole(keyboard)
      if Mode.test
        Builtins.y2milestone("Test mode - NOT setting keyboard")
      elsif Arch.board_iseries || Arch.s390 # workaround for bug #39025
        Builtins.y2milestone("not calling loadkeys on iseries")
      else
        SetKeyboard(keyboard)

        Builtins.y2milestone("Setting console keyboard to: <%1>", @current_kbd)
        Builtins.y2milestone("loadkeys command: <%1>", @ckb_cmd)

        SCR.Execute(path(".target.bash"), @ckb_cmd)
        UI.SetKeyboard
      end
      @ckb_cmd
    end # SetConsole()



    # Set the X11 keyboard to the given keyboard language.
    #
    # @param	Keyboard language e.g.  "english-us"
    #
    # @return  The xkbset command that has been executed to do it.
    #		(also stored in Keyboard::xkb_cmd)
    def SetX11(keyboard)
      if Mode.test
        Builtins.y2milestone("Test mode - would have called:\n %1", @xkb_cmd)
      else
        # Actually do it only if we are in graphical mode.
        #
        textmode = Linuxrc.text
        if !Stage.initial || Mode.live_installation
          display_info = UI.GetDisplayInfo
          textmode = Ops.get_boolean(display_info, "TextMode", false)
        end
        display = Builtins.getenv("DISPLAY")
        if textmode
          Builtins.y2milestone("Not setting X keyboard due to text mode")
        # check if we are running over ssh: bnc#539218,c4
        elsif Ops.greater_or_equal(
            Builtins.tointeger(
              Ops.get(Builtins.splitstring(display, ":"), 1, "0")
            ),
            10
          )
          Builtins.y2milestone("Not setting X keyboard: running over ssh")
        elsif Ops.greater_than(Builtins.size(@xkb_cmd), 0)
          SetKeyboard(keyboard)
          Builtins.y2milestone("Setting X11 keyboard to: <%1>", @current_kbd)
          Builtins.y2milestone("Setting X11 keyboard:\n %1", @xkb_cmd)
          SCR.Execute(path(".target.bash"), @xkb_cmd)
          # bnc#371756: enable autorepeat
          if Stage.initial && !Mode.live_installation && !xen_running
            cmd = "xset r on"
            Builtins.y2milestone(
              "calling xset to fix autorepeat problem: %1",
              cmd
            )
            SCR.Execute(path(".target.bash"), cmd)
          end
        end
      end
      @xkb_cmd
    end # SetX11()



    # Set()
    #
    # Set the keyboard to the given keyboard language.
    #
    # @param   Keyboard language e.g.  "english-us"
    #
    # @return  [void]
    #
    # @see     SetX11(), SetConsole()

    def Set(keyboard)
      Builtins.y2milestone("set to %1", keyboard)
      if Mode.config
        @current_kbd = keyboard
        @name = GetKeyboardName(@current_kbd)
        return
      end

      SetConsole(keyboard)
      SetX11(keyboard)
      if Stage.initial && !Mode.live_installation
        yinf = {}
        yinf_ref = arg_ref(yinf)
        AsciiFile.SetDelimiter(yinf_ref, " ")
        yinf = yinf_ref.value
        yinf_ref = arg_ref(yinf)
        AsciiFile.ReadFile(yinf_ref, "/etc/yast.inf")
        yinf = yinf_ref.value
        lines = AsciiFile.FindLineField(yinf, 0, "Keytable:")
        if Ops.greater_than(Builtins.size(lines), 0)
          yinf_ref = arg_ref(yinf)
          AsciiFile.ChangeLineField(
            yinf_ref,
            Ops.get_integer(lines, 0, -1),
            1,
            @keymap
          )
          yinf = yinf_ref.value
        else
          yinf_ref = arg_ref(yinf)
          AsciiFile.AppendLine(yinf_ref, ["Keytable:", @keymap])
          yinf = yinf_ref.value
        end
        yinf_ref = arg_ref(yinf)
        AsciiFile.RewriteFile(yinf_ref, "/etc/yast.inf")
        yinf = yinf_ref.value
      end

      nil
    end


    # MakeProposal()
    #
    # Return proposal string and set system keyboard.
    #
    # @param [Boolean] force_reset
    #		boolean language_changed
    #
    # @return	[String]	user readable description.
    #		If force_reset is true reset the module to the keyboard
    #		stored in default_kbd.

    def MakeProposal(force_reset, language_changed)
      Builtins.y2milestone("force_reset: %1", force_reset)
      Builtins.y2milestone("language_changed: %1", language_changed)

      if force_reset
        # If user wants to reset do it if a default is available.
        if @default_kbd != ""
          Set(@default_kbd) # reset
        end

        # Reset user_decision flag.
        @user_decision = false
        @restore_called = false # no reset
      else
        # Only follow the language if the user has never actively chosen
        # a keyboard. The indicator for this is user_decision which is
        # set from outside the module.
        if @user_decision || Mode.update && !Stage.initial || Mode.autoinst ||
            Mode.live_installation ||
            ProductFeatures.GetStringFeature("globals", "keyboard") != ""
          if language_changed
            Builtins.y2milestone(
              "User has chosen a keyboard; not following language - only retranslation."
            )

            Set(@current_kbd)
          end
        else
          # User has not yet chosen a keyboard ==> follow language.
          local_kbd = GetKeyboardForLanguage(Language.language, "english-us")
          if local_kbd != ""
            Set(local_kbd)
          elsif language_changed
            Builtins.y2error("Can't follow language - only retranslation")
            Set(@current_kbd)
          end
        end
      end
      @name
    end # MakeProposal()


    # CalledRestore()
    #
    # Return if the kbd values have already been read from
    # /etc/sysconfig/keyboard
    #
    def CalledRestore
      @restore_called
    end

    # Selection()
    #
    # Get the map of translated keyboard names.
    #
    # @return	[Hash] of $[ keyboard_code : keyboard_name, ...] for all known
    #		keyboards. 'keyboard_code' is used internally in Set and Get
    #		functions. 'keyboard_name' is a user-readable string.
    #
    def Selection
      # Get the reduced keyboard DB.
      #
      keyboards = get_reduced_keyboard_db
      translate = ""
      trans_str = ""

      Builtins.mapmap(keyboards) do |keyboard_code, keyboard_value|
        translate = Ops.get_string(keyboard_value, 0, "")
        trans_str = Builtins.eval(translate)
        { keyboard_code => trans_str }
      end
    end

    # Return item list of keyboard items, sorted according to current language
    def GetKeyboardItems
      ret = Builtins.maplist(Selection()) do |code, name|
        Item(Id(code), name, @current_kbd == code)
      end
      Builtins.sort(ret) do |a, b|
        # bnc#385172: must use < instead of <=, the following means:
        # strcoll(x) <= strcoll(y) && strcoll(x) != strcoll(y)
        lsorted = Builtins.lsort(
          [Ops.get_string(a, 1, ""), Ops.get_string(b, 1, "")]
        )
        lsorted_r = Builtins.lsort(
          [Ops.get_string(b, 1, ""), Ops.get_string(a, 1, "")]
        )
        Ops.get_string(lsorted, 0, "") == Ops.get_string(a, 1, "") &&
          lsorted == lsorted_r
      end
    end


    # SetExpertValues()
    #
    # Set the values of the various expert setting
    #
    # @param [Hash] val     map with new values of expert settings
    def SetExpertValues(val)
      val = deep_copy(val)
      orig_values = GetExpertValues()

      if Builtins.haskey(val, "rate") &&
          Ops.greater_than(Builtins.size(Ops.get_string(val, "rate", "")), 0)
        @kbd_rate = Ops.get_string(val, "rate", "")
      end
      if Builtins.haskey(val, "delay") &&
          Ops.greater_than(Builtins.size(Ops.get_string(val, "delay", "")), 0)
        @kbd_delay = Ops.get_string(val, "delay", "")
      end
      if Builtins.haskey(val, "numlock")
        @kbd_numlock = Ops.get_string(val, "numlock", "")
      end
      if Builtins.haskey(val, "discaps")
        @kbd_disable_capslock = Ops.get_boolean(val, "discaps", false) ? "yes" : "no"
      end

      if !@ExpertSettingsChanged && orig_values != GetExpertValues()
        @ExpertSettingsChanged = true
      end

      nil
    end

    # set the keayboard layout according to given language
    def SetKeyboardForLanguage(lang)
      lkbd = GetKeyboardForLanguage(lang, "english-us")
      Builtins.y2milestone("language %1 proposed keyboard %2", lang, lkbd)
      Set(lkbd) if lkbd != ""

      nil
    end

    def SetKeyboardForLang(lang)
      SetKeyboardForLanguage(lang)
    end

    def SetKeyboardDefault
      Builtins.y2milestone("SetKeyboardDefault to %1", @current_kbd)
      @default_kbd = @current_kbd

      nil
    end


    # Special function for update mode only.
    # Checks for the keyboard layout on the system which should be updated and if it
    # differs from current one, opens a popup with the offer to change the layout.
    # See discussion in bug #71069
    # @param [String] destdir path to the mounted system to update (e.g. "/mnt")
    def CheckKeyboardDuringUpdate(destdir)
      # autoupgrade is not interactive, therefore skip this check and use data
      # from profile directly
      return if Mode.autoupgrade

      target_kbd = Misc.CustomSysconfigRead(
        "YAST_KEYBOARD",
        @current_kbd,
        Ops.add(destdir, "/etc/sysconfig/keyboard")
      )
      pos = Builtins.find(target_kbd, ",")
      if pos != nil && Ops.greater_than(pos, 0)
        target_kbd = Builtins.substring(target_kbd, 0, pos)
      end

      keyboards = get_reduced_keyboard_db

      if target_kbd != @current_kbd &&
          Ops.get_list(keyboards, target_kbd, []) != []
        Builtins.y2milestone(
          "current_kbd: %1, target_kbd: %2",
          @current_kbd,
          target_kbd
        )

        target_name = GetKeyboardName(target_kbd)

        UI.OpenDialog(
          Opt(:decorated),
          HBox(
            HSpacing(1.5),
            VBox(
              HSpacing(40),
              VSpacing(0.5),
              # label text: user can choose the keyboard from the updated system
              # or continue with the one defined by his language.
              # 2 radio-buttons follow this label.
              # Such keyboard layout is used only for the time of the update,
              # it is not saved to the system.
              Left(
                Label(
                  _(
                    "You are currently using a keyboard layout\n" +
                      "different from the one in the system to update.\n" +
                      "Select the layout to use during update:"
                  )
                )
              ),
              VSpacing(0.5),
              RadioButtonGroup(
                VBox(
                  Left(RadioButton(Id(:current), @name)),
                  Left(RadioButton(Id(:target), target_name, true))
                )
              ),
              VSpacing(0.5),
              ButtonBox(
                PushButton(Id(:ok), Opt(:default, :key_F10), Label.OKButton),
                PushButton(Id(:cancel), Opt(:key_F9), Label.CancelButton)
              ),
              VSpacing(0.5)
            ),
            HSpacing(1.5)
          )
        )
        ret = UI.UserInput

        if ret == :ok && Convert.to_boolean(UI.QueryWidget(Id(:target), :Value))
          Set(target_kbd)
          @user_decision = true
        end

        UI.CloseDialog
      end

      nil
    end

    # AutoYaST interface function: Get the Keyboard configuration from a map.
    # @param [Hash] settings imported map
    # @return success
    def Import(settings)
      settings = deep_copy(settings)
      # Read was not called -> do the init
      Read() if @expert_on_entry == {}

      Set(Ops.get_string(settings, "keymap", @current_kbd))
      SetExpertValues(Ops.get_map(settings, "keyboard_values", {}))
      true
    end

    # AutoYaST interface function: Return the Keyboard configuration as a map.
    # @return [Hash] with the settings
    def Export
      diff_values = {}
      Builtins.foreach(
        Convert.convert(
          GetExpertValues(),
          :from => "map",
          :to   => "map <string, any>"
        )
      ) do |key, val|
        Ops.set(diff_values, key, val) if Ops.get(@expert_on_entry, key) != val
      end
      ret = { "keymap" => @current_kbd }
      Ops.set(ret, "keyboard_values", diff_values) if diff_values != {}
      deep_copy(ret)
    end

    # AutoYaST interface function: Return the summary of Keyboard configuration as a map.
    # @return summary string (html)
    def Summary
      Yast.import "HTML"

      ret = [
        # summary label
        Builtins.sformat(_("Current Keyboard Layout: %1"), @name)
      ]
      HTML.List(ret)
    end

    publish :variable => :kb_model, :type => "string"
    publish :variable => :XkbModel, :type => "string"
    publish :variable => :XkbLayout, :type => "string"
    publish :variable => :XkbVariant, :type => "string"
    publish :variable => :keymap, :type => "string"
    publish :variable => :compose_table, :type => "string"
    publish :variable => :XkbOptions, :type => "string"
    publish :variable => :LeftAlt, :type => "string"
    publish :variable => :RightAlt, :type => "string"
    publish :variable => :RightCtl, :type => "string"
    publish :variable => :ScrollLock, :type => "string"
    publish :variable => :Apply, :type => "string"
    publish :variable => :ckb_cmd, :type => "string"
    publish :variable => :xkb_cmd, :type => "string"
    publish :variable => :current_kbd, :type => "string"
    publish :variable => :keyboard_on_entry, :type => "string"
    publish :variable => :expert_on_entry, :type => "map"
    publish :variable => :default_kbd, :type => "string"
    publish :variable => :user_decision, :type => "boolean"
    publish :variable => :unique_key, :type => "string"
    publish :variable => :ExpertSettingsChanged, :type => "boolean"
    publish :function => :Set, :type => "void (string)"
    publish :function => :keymap2yast, :type => "map <string, string> ()"
    publish :function => :GetX11KeyData, :type => "map (string)"
    publish :function => :GetExpertValues, :type => "map ()"
    publish :function => :get_lang2keyboard, :type => "map ()"
    publish :function => :GetKeyboardForLanguage, :type => "string (string, string)"
    publish :function => :SetKeyboard, :type => "boolean (string)"
    publish :function => :Restore, :type => "boolean ()"
    publish :function => :Probe, :type => "void ()"
    publish :function => :Keyboard, :type => "void ()"
    publish :function => :Read, :type => "boolean ()"
    publish :function => :Modified, :type => "boolean ()"
    publish :function => :Save, :type => "void ()"
    publish :function => :Name, :type => "string ()"
    publish :function => :SetConsole, :type => "string (string)"
    publish :function => :SetX11, :type => "string (string)"
    publish :function => :MakeProposal, :type => "string (boolean, boolean)"
    publish :function => :CalledRestore, :type => "boolean ()"
    publish :function => :Selection, :type => "map <string, string> ()"
    publish :function => :GetKeyboardItems, :type => "list <term> ()"
    publish :function => :SetExpertValues, :type => "void (map)"
    publish :function => :SetKeyboardForLanguage, :type => "void (string)"
    publish :function => :SetKeyboardForLang, :type => "void (string)"
    publish :function => :SetKeyboardDefault, :type => "void ()"
    publish :function => :CheckKeyboardDuringUpdate, :type => "void (string)"
    publish :function => :Import, :type => "boolean (map)"
    publish :function => :Export, :type => "map ()"
    publish :function => :Summary, :type => "string ()"
  end

  Keyboard = KeyboardClass.new
  Keyboard.main
end
