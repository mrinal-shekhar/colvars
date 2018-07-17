# Colvars Dashboard -- based on the Colvars Module for VMD
# Jérôme Hénin <henin@ibpc.fr> 2018

# At this stage, only acts on the "top" molecule
# could query cvm to know what molecule is concerned

namespace eval ::cv_dashboard {
  variable current_frame 0
  variable cv_values {}
  variable cvs {}
  variable track_frame 1 ;# start tracking by default
  variable being_edited
  variable backup_cfg
  variable plothandle
}


# Call the "cv" interface to Colvars, catching errors and displaying them to the user
proc run_cv args  {
  if [ catch { cv {*}$args } res ] {
    tk_messageBox -icon error -title "Colvars error" -parent .cv_dashboard_window\
      -message "Error running command:\n\n$args" -detail "$res"
    return -1
  }
  return $res
}


# Refresh the table with a list of existing CVs and their values
proc ::cv_dashboard::refresh_table {} {
  set w .cv_dashboard_window
  set ::cv_dashboard::cvs [run_cv list]
  update_frame vmd_frame [molinfo top] w
}

proc ::cv_dashboard::refresh_values {} {
  run_cv update
  set w .cv_dashboard_window
  set ::cv_dashboard::cv_values {}
  foreach c [run_cv list] {
    lappend ::cv_dashboard::cv_values [format_value [run_cv colvar $c value] ]
  }
}

proc ::cv_dashboard::update_frame { name molid op } {
  # name == vmd_frame
  # molid == molecule id of the newly changed frame
  # op == w
  global vmd_frame
  variable ::cv_dashboard::plothandle

  if { $molid != [molinfo top] } {
    return
  }
  set f [molinfo $molid get frame]

  set ::cv_dashboard::current_frame $f
  run_cv frame $f
  refresh_values

  if [info exists plothandle] {
    # detect if plot was closed
    if [catch {$plothandle getpath}] {
      unset plothandle
    } else {
      # we tinker a little with Multiplot's internals to get access to its Tk canvas
      # necessary because Multiplot does not expose an interface to draw & delete
      # objects without redrawing the whole plot - which takes too long for this
      set ns [namespace qualifiers $plothandle]
      set y1 [set ${ns}::yplotmin]
      set y2 [set ${ns}::yplotmax]
      set xplotmin [set ${ns}::xplotmin]
      set scalex [set ${ns}::scalex]
      set xmin [set ${ns}::xmin]
      set x [expr $xplotmin+($scalex*($f-$xmin))]

      set canv "[set ${ns}::w].f.cf"
      $canv delete step_line
      $canv create line  $x $y1 $x $y2 -fill blue -tags step_line
    }
  }
}


proc ::cv_dashboard::format_value val {
  if {[llength $val] == 1} {
    return [format "%.4g" $val]
  } else {
    set s "{("
    foreach v [lrange $val 0 end-1] {
      append s "[format_value $v] "
    }
    append s "[format_value [lindex $val end]])}"
    return $s
  }
}


proc ::cv_dashboard::selected {} {
  set w .cv_dashboard_window
  set l {}
  refresh_table ;# to make sure selected colvars haven't been deleted
  foreach i [$w.cvtable curselection] {
    lappend l [lindex $::cv_dashboard::cvs $i]
  }
  return $l
}


# Enable or disable real-time tracking of VMD frame
proc ::cv_dashboard::change_track_frame {} {
  global vmd_frame

  set molid [molinfo top]
  if {$::cv_dashboard::track_frame} {
    trace add variable vmd_frame($molid) write ::cv_dashboard::update_frame
    update_frame vmd_frame [molinfo top] w
  } else {
    trace remove variable vmd_frame($molid) write ::cv_dashboard::update_frame
  }
}

# Load config from file
proc ::cv_dashboard::load {} {
  set path [tk_getOpenFile -filetypes {{"Colvars cfg" .in} {"Colvars cfg" .colvars}}]
  if [string compare $path ""] {
    run_cv configfile $path
    refresh_table
  }
}


# Save config of colvars to file (can we do it w/ biases ? need bias type keyword)
proc ::cv_dashboard::save {} {

  set path [tk_getSaveFile -filetypes {{"Colvars cfg" .in} {"Colvars cfg" .colvars}}]

  if [string compare $path ""] {
    set cfg ""
    foreach c [run_cv list] {
        append cfg "colvar {"
        append cfg [run_cv colvar $c getconfig]
        append cfg "}\n\n"
    }

    set o [open $path w]
    puts $o $cfg
    close $o
  }
}


proc ::cv_dashboard::del {} {

  foreach c [selected] {
    # workaround bug in colvars pre-2018-07-02
    if {[string compare [run_cv version] "2018-07-02"] == -1} {
      foreach b [run_cv list biases] {
        if [string match *colvars*$c* [run_cv bias $b getconfig]] {
          puts "Bug workaround: deleting bias $b"
          run_cv bias $b delete
        }
      }
    }
    run_cv colvar $c delete
  }
  refresh_table
}


proc ::cv_dashboard::add {} {
  edit true
}


# Enable or disable real-time tracking of VMD frame
proc ::cv_dashboard::edit { {add false} } {
  set cfg ""

  if $add {
    # do not remove existing vars
    set cvs {}
    # Provide simple template
    set cfg "colvar {\n  name d\n  distance {\n    group1 { atomNumbers 1 2 }\n    group2 { atomNumbers 3 4 }\n  }\n}\n"
  } else {
    set cvs [selected]
    if {[llength $cvs] == 0} {
      # If no selection, edit all variables
      set cvs $::cv_dashboard::cvs
    }
    foreach c $cvs {
      append cfg "colvar {"
      append cfg [run_cv colvar $c getconfig]
      append cfg "}\n\n"
    }
    set ::cv_dashboard::backup_cfg $cfg
  }
  set w .cv_dashboard_window
  set editor [toplevel $w.editor]
  wm title $editor "Colvar config editor"
  tk::text $w.editor.text -undo 1 -yscrollcommand [list $w.editor.vsb set]
  ttk::scrollbar $w.editor.vsb -orient vertical -command [list $w.editor.text yview]

  $w.editor.text insert 1.0 $cfg
  set ::cv_dashboard::being_edited $cvs

  grid $w.editor.text -row 0 -columnspan 2 -sticky nsew
  grid $w.editor.vsb -row 0 -column 2 -sticky ns

  set gridrow 1

  ttk::button $w.editor.apply -text "Apply" -command ::cv_dashboard::edit_apply
  ttk::button $w.editor.cancel -text "Cancel" -command ::cv_dashboard::edit_cancel
  grid $w.editor.apply -row $gridrow -column 0 -sticky e
  grid $w.editor.cancel -row $gridrow -column 1 -sticky w

  grid columnconfigure $w.editor 0 -weight 1
  grid columnconfigure $w.editor 1 -weight 1
  grid rowconfigure $w.editor 0 -weight 1


}


proc ::cv_dashboard::edit_apply {} {
  set w .cv_dashboard_window
  foreach c $::cv_dashboard::being_edited {
    puts "Deleting $c"
    run_cv colvar $c delete
    puts [cv list]
  }
  set cfg [$w.editor.text get 1.0 end-1c]
  if { $cfg != "" } {
    set res [run_cv config $cfg]
    if { [string compare $res ""] } {
      # error: restore backed up cfg
      run_cv config $::cv_dashboard::backup_cfg
    }
  }
  set ::cv_dashboard::being_edited {}
  destroy $w.editor
  refresh_table
}


proc ::cv_dashboard::reset {} {
  run_cv reset
  refresh_table
}


proc ::cv_dashboard::edit_cancel {} {
  set w .cv_dashboard_window
  set ::cv_dashboard::being_edited {}
  destroy $w.editor
}


proc ::cv_dashboard::plot {} {
  variable ::cv_dashboard::plothandle

  set nf [molinfo top get numframes]
  set x {}
  for {set f 0} {$f < $nf} {incr f} { lappend x $f }

  set cvs [selected]
  if { [llength $cvs] == 0 } {
    # If no selection, plot all variables
    set cvs $::cv_dashboard::cvs
    if { [llength $cvs] == 0 } {
      return
    }
  }

  foreach c $cvs {
    set val [run_cv colvar $c update]
    set size [llength $val]
    if { $size == 1 } {
      set names($c) $c
      set y($c) {}
    } else {
      for {set i 1} {$i <= $size} {incr i} {
        set n $c; append n "_$i"
        lappend names($c) $n
        set y($n) {}
      }
    }
  }

  for {set f 0} {$f< $nf} {incr f} {
    run_cv frame $f
    foreach c $cvs {
      set val [run_cv colvar $c update]
      foreach ni $names($c) vi $val {
        lappend y($ni) $vi
      }
    }
  }
  set plothandle [multiplot -title {Colvars trajectory   [left-click, keyb arrows (+ Shift/Ctrl) to navigate & zoom, v/h to fit vert/horizontally]} \
      -xlabel "Frame" -ylabel "Value" -nostats]
  foreach c $cvs {
    foreach n $names($c) {
      $plothandle add $x $y($n) -legend $n
    }
  }
  $plothandle replot

  # bind the plot window to a callback that will change the frame whenever the user clicks the plot
  set plot_ns [namespace qualifiers $::cv_dashboard::plothandle]
  bind [set ${plot_ns}::w] <Button-1> { ::cv_dashboard::plot_clicked %x %y }
  bind [set ${plot_ns}::w] <Left> { ::cv_dashboard::chg_frame -1 }
  bind [set ${plot_ns}::w] <Right> { ::cv_dashboard::chg_frame 1 }
  bind [set ${plot_ns}::w] <Shift-Left> { ::cv_dashboard::chg_frame -10 }
  bind [set ${plot_ns}::w] <Shift-Right> { ::cv_dashboard::chg_frame 10 }
  bind [set ${plot_ns}::w] <Control-Left> { ::cv_dashboard::chg_frame -50 }
  bind [set ${plot_ns}::w] <Control-Right> { ::cv_dashboard::chg_frame 50 }
  bind [set ${plot_ns}::w] <Up>  { ::cv_dashboard::zoom 0.25 }
  bind [set ${plot_ns}::w] <Down>  { ::cv_dashboard::zoom 4 }
  bind [set ${plot_ns}::w] <Shift-Up>  { ::cv_dashboard::zoom 0.0625 }
  bind [set ${plot_ns}::w] <Shift-Down>  { ::cv_dashboard::zoom 16 }
  bind [set ${plot_ns}::w] <v> { ::cv_dashboard::fit_vertically }
  bind [set ${plot_ns}::w] <h> { ::cv_dashboard::fit_horizontally }
}


proc ::cv_dashboard::plot_clicked { x y } {

  set ns [namespace qualifiers $::cv_dashboard::plothandle]
  set xplotmin [set ${ns}::xplotmin]
  set xplotmax [set ${ns}::xplotmax]
  set yplotmin [set ${ns}::yplotmin]
  set yplotmax [set ${ns}::yplotmax]
  set scalex [set ${ns}::scalex]
  set xmin [set ${ns}::xmin]

  # note: ymax < ymin because of weird screen convention
  if { [expr {($x < $xplotmin) || ($x > $xplotmax) || ($y > $yplotmin) || ($y < $yplotmax)}] } {
    return
  }

  animate goto [expr { ($x - $xplotmin) / $scalex + $xmin}]
  refresh_table
}

proc ::cv_dashboard::chg_frame { shift } {
  set f [expr $::cv_dashboard::current_frame + $shift]
  catch "animate goto $f"
  refresh_table
}


proc ::cv_dashboard::zoom { factor } {
  variable ::cv_dashboard::plothandle

  set ns [namespace qualifiers $plothandle]
  set xmin [set ${ns}::xmin]
  set xmax [set ${ns}::xmax]

  set f $::cv_dashboard::current_frame
  # rescale current half-width
  set half_width [expr { int (($xmax - $xmin) * $factor / 2)}]
  if { $half_width < 1 } {
    # Don't collapse the x axis to a single point
    return
  }
  set fmin [expr { $f - $half_width }]
  if {$fmin < 0} { set fmin 0 }

  set fmax [expr { $f + $half_width }]
  set max_f [expr [molinfo top get numframes] - 1]
  if {$fmax > $max_f} { set fmax $max_f }

  $plothandle configure -xmin $fmin -xmax $fmax -plot
  update_frame vmd_frame [molinfo top] w
}


proc ::cv_dashboard::fit_vertically {} {
  variable ::cv_dashboard::plothandle

  set ns [namespace qualifiers $plothandle]
  set xmin [set ${ns}::xmin]
  set xmax [set ${ns}::xmax]
  set ydata [$plothandle ydata]
  set ymin [lindex [lindex $ydata 0] $xmin]
  set ymax $ymin
  foreach yset $ydata {
    for { set f $xmin } { $f <= $xmax } { incr f } {
      set y [lindex $yset $f]
      if { $y > $ymax } { set ymax $y }
      if { $y < $ymin } { set ymin $y }
    }
  }
  $plothandle configure -ymin $ymin -ymax $ymax -plot
  update_frame vmd_frame [molinfo top] w
}


proc ::cv_dashboard::fit_horizontally {} {
  variable ::cv_dashboard::plothandle

  set ns [namespace qualifiers $plothandle]
  set xdata [$plothandle xdata]
  set xmax [lindex [lindex $xdata 0] end]
  $plothandle configure -xmin 0 -xmax $xmax -plot
  fit_vertically
  update_frame vmd_frame [molinfo top] w
}


# The main window
proc ::cv_dashboard::createWindow {} {
  set w [toplevel .cv_dashboard_window]

  wm title $w "Colvars dashboard"
  wm protocol $w WM_DELETE_WINDOW {
    # window destructor that removes the trace we put in place, so they don't accumulate
    # if loaded multiple times
    set molid [molinfo top]
    trace remove variable vmd_frame($molid) write ::cv_dashboard::update_frame
    destroy .cv_dashboard_window
  }

  # setup Colvars if not already there
  if [catch { cv version}] {
    run_cv molid top
  }
  set gridrow 0
  grid [ttk::button $w.load -text "Load file" -command ::cv_dashboard::load -padding "2 0 2 0"] -row $gridrow -column 0 -pady 5 -padx 2 -sticky nsew
  grid [ttk::button $w.save -text "Save colvars" -command ::cv_dashboard::save -padding "2 0 2 0"] -row $gridrow -column 1 -pady 5 -padx 2 -sticky nsew
  grid [ttk::button $w.reset -text "Reset" -command ::cv_dashboard::reset -padding "2 0 2 0"] -row $gridrow -column 2 -pady 5 -padx 2 -sticky nsew

  tablelist::tablelist $w.cvtable -columns {
    0 Colvars
  } -stretch all -selectmode extended -selecttype row -listvariable ::cv_dashboard::cvs
  tablelist::tablelist $w.valuetable -columns {
    0 Values
  } -stretch all -listvariable ::cv_dashboard::cv_values

  refresh_table

  incr gridrow
  grid $w.cvtable -row $gridrow -column 0 -sticky news
  grid $w.valuetable -row $gridrow -column 1 -sticky news -columnspan 2
  grid rowconfigure $w $gridrow -weight 1

  incr gridrow
  grid [ttk::button $w.edit -text "Edit" -command ::cv_dashboard::edit -padding "2 0 2 0"] -row $gridrow -column 0 -pady 5 -padx 2 -sticky nsew
  grid [ttk::button $w.add -text "Add" -command ::cv_dashboard::add -padding "2 0 2 0"] -row $gridrow -column 1 -pady 5 -padx 2 -sticky nsew
  grid [ttk::button $w.del -text "Delete" -command ::cv_dashboard::del -padding "2 0 2 0"] -row $gridrow -column 2 -pady 5 -padx 2 -sticky nsew

  incr gridrow
  grid [ttk::button $w.plot -text "Interactive plot" -command ::cv_dashboard::plot -padding "2 0 2 0"] -row $gridrow -column 0 -pady 5 -padx 2 -sticky nsew
  grid [ttk::button $w.refresh -text "Refresh" -command ::cv_dashboard::refresh_table -padding "2 0 2 0"] -row $gridrow -column 1 -pady 5 -padx 2 -sticky nsew

  incr gridrow
  grid [label $w.frameTxt -text "Frame:"] -row $gridrow -column 0 -pady 5 -padx 2 -sticky nsew
  grid [label $w.frame -textvariable ::cv_dashboard::current_frame] -row $gridrow -column 1 -pady 5 -padx 2 -sticky nsew
  grid [ttk::checkbutton $w.trackFrame -text "Track" -command ::cv_dashboard::change_track_frame -variable ::cv_dashboard::track_frame]  -row $gridrow -column 2  -pady 5 -padx 2 -sticky nsew
  change_track_frame ;# activate tracking if necessary

  grid columnconfigure $w 0 -weight 1
  grid columnconfigure $w 1 -weight 1
  grid columnconfigure $w 2 -weight 1
}

# If window already exists, destroy it
catch { destroy .cv_dashboard_window }
::cv_dashboard::createWindow