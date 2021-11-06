using Gtk;
using Gdk;

/*
This is just a development file, to add a new feature to shuffler. The feature
is a popup that will calculate the active window's size & position, converts
it in to a representation on a grid, up to a arbitrary max cols/rows.
from the popup, user can add it to either a new rule for the active window's
WMCLASS, or add it to an existing (shuffler) layout. Once set, user can fine-
tune from shuffler control -> rules/layouts.
*/

/* get client -> get active window / get window data -> get monitor for
size & position calculations -> produce grid, size on grid/position on grid.
*/



namespace ShufflerGridDisplayWindow {

    public class GridDisplayWindow : Gtk.Window {
        /*
        This window tries to produce a gridsize, the grid position and span
        of the active window on it, to show a good reflection of the window
        in a grid. To do so, it calculates cols/rows of an appropriate grid,
        gridx and gridy, xspan and yspan of the window.
        These arguments are thrown to ShufflerGridDisplay.ShowShufflerGrid,
        to produce the actual representation.
        */

        ShufflerInfoClient? client;
        [DBus (name = "org.UbuntuBudgie.ShufflerInfoDaemon")]

        interface ShufflerInfoClient : Object {
            public abstract GLib.HashTable<string, Variant> get_winsdata() throws Error;
            public abstract int getactivewin() throws Error;
            public abstract int check_windowvalid(int wid) throws Error;
            public abstract GLib.HashTable<string, Variant> get_monitorgeometry() throws Error;
            public abstract string getactivemon_name() throws Error;

        }

        private void get_client() {
            print("checking client\n");
            try {
                client = Bus.get_proxy_sync (
                    BusType.SESSION, "org.UbuntuBudgie.ShufflerInfoDaemon",
                    ("/org/ubuntubudgie/shufflerinfodaemon")
                );
            }
            catch (Error e) {
                    stderr.printf ("%s\n", e.message);
            }
        }

        private int[]? get_windata() {
            // get x, y, wdth, hght on the active window, null if invalid
            Variant? currwindata = null;
            try {
                GLib.HashTable<string, Variant> windata = client.get_winsdata();
                GLib.List<unowned string> windata_keys = windata.get_keys();
                string winkey = client.getactivewin().to_string();
                // select the active window from windata
                foreach (string k in windata_keys) {
                    if (k == winkey) {
                        currwindata = windata[k];
                        //  print(@"foundit! $k\n");
                    }
                }
                int xpos = (int)currwindata.get_child_value(3);
                int ypos = (int)currwindata.get_child_value(4);
                int wdth = (int)currwindata.get_child_value(5);
                int hght = (int)currwindata.get_child_value(6);
                print(@"from win method: $xpos, $ypos, $wdth, $hght\n");
                return {xpos, ypos, wdth, hght};
            }
            catch (Error e) {
                stderr.printf ("%s\n", e.message);
            }
            return null;
        }

        private int[]? get_monitordata() {
             // get x, y, wdth, hght on the active monitor, null if invalid
            Variant? currmondata = null;
            try {
                GLib.HashTable<string, Variant> monitordata = client.get_monitorgeometry ();
                GLib.List<unowned string> monitordata_keys = monitordata.get_keys ();
                string monkey = client.getactivemon_name();
                foreach (string k in monitordata_keys) {
                    if (k == monkey) {
                        currmondata = monitordata[k];
                        print(@"found monitor $k\n");
                    }
                }
                int monx = (int)currmondata.get_child_value(0);
                int mony = (int)currmondata.get_child_value(1);
                int monwidth = (int)currmondata.get_child_value(2);
                int monheight = (int)currmondata.get_child_value(3);
                print(@"from mon method: monx: $monx, mony: $mony, monwidth: $monwidth, monheight: $monheight\n");
                return {monx, mony, monwidth, monheight};
            }
            catch (Error e) {
                stderr.printf ("%s\n", e.message);
            }
            return null;
        }

        ///////////////////////////////////////////
        ///////////////////////////////////////////
        // get window & monitordata -> null on failure
        ///////////////////////////////////////////
        ///////////////////////////////////////////

        private int[] get_wingridpos(
            int maxdivisions, int screensize, int winsize, int winpos
        ) {
            /*
            In order to create a preview of the targeted window position on grid,
            given the windowsize, screensize and window position (px), find out
            what is the relative size to the screen, find out what number of
            cells & span reflexes best the relative size, assume the best grid-
            position.
            This method has to run separately on both axes x/y.
            */
            print(@"input: winsize: $winsize, winpos: $winpos, screensize: $screensize\n");
            double relative_winsize = (double)winsize/(double)screensize;
            print(@"$relative_winsize\n");
            int diff = 20000; // just throw a high number
            int found_divisions = 0; // n_divisions
            int foundspan = 0;
            int foundcellwidth = 0;
            int found_wingridpos = 0;
            for (int divisions=1; divisions<=maxdivisions; divisions++) {
                int cellsize = (int)((float)screensize/(float)divisions);
                for (int curr_ncells=1; curr_ncells<=divisions; curr_ncells++) {
                    int spansize = curr_ncells * cellsize;
                    int newdiff = (winsize - spansize).abs();
                    if (newdiff < diff) {
                        diff = newdiff;
                        found_divisions = divisions;
                        foundspan = curr_ncells;
                        foundcellwidth = cellsize;
                    }
                }
            }
            // so now we have the divisions, let's find the position
            int currdif = 20000;
            for (int gridpos=0; gridpos<found_divisions; gridpos++) {
                int posdiff = ((gridpos * foundcellwidth) - winpos).abs();
                if (posdiff < currdif) {
                    currdif = posdiff;
                    found_wingridpos = gridpos;
                }
            }
            return {found_divisions, found_wingridpos, foundspan};
        }





        public GridDisplayWindow() {
            this.destroy.connect(Gtk.main_quit);
            get_client();
            // window x, y, wdth, hght (px)
            int[]? windata = get_windata();
            // monitor (wa!) x, y, wdth, hght (real px, unscaled)
            int[]? mondata = get_monitordata();
            
            // Don't forget monitor position in layout x/y!!!!!

            // not so charming, change please
            if (mondata != null && windata != null) {
                // int maxdivisions, int screensize, int winsize, int winpos
                // get x-data
                int relative_xposition = windata[0]-mondata[0];
                print(@"real xposition = $relative_xposition\n");
                int relative_yposition = windata[1]-mondata[1];
                print(@"real yposition = $relative_yposition\n");
                int[] xdata = get_wingridpos(6, mondata[2], windata[2], relative_xposition);
                int[] ydata = get_wingridpos(4, mondata[3], windata[3], relative_yposition);
                int cols = xdata[0];
                int winxgridpos = xdata[1];
                int xspan = xdata[2];
                int rows = ydata[0];
                int winygridpos = ydata[1];
                int yspan = ydata[2];
                print(@"cols: $cols, xpos: $winxgridpos, xspan: $xspan\n");
                print(@"rows: $rows, ypos: $winygridpos, yspan: $yspan\n");
                Grid maingrid = new Gtk.Grid();
                //int cols, int rows, int gridx, int gridy, int xspan, int yspan,
                Grid showgrid = new ShufflerGridDisplay.ShowShufflerGrid(
                    cols, rows, winxgridpos, winygridpos, xspan, yspan
                );
                maingrid.attach(showgrid, 0, 0, 1, 1); // 0, 0, 1, 1 for now
                this.add(maingrid);
                this.show_all();
            }
        }
    }

    public static void main(string[] args) {
        Gtk.init(ref args);
        new GridDisplayWindow();
        Gtk.main();
    }
}


































namespace ShufflerGridDisplay {

    private class GridDisplayButton : Gtk.Button {

        /*
        GridDisplayButton produces a (single) button, representing a grid
        cell. Color is either grey (bg cell) or blue-ish (window cell), d epen-
        ding on the argument "windowcell" (true/false).
        */

        public GridDisplayButton (bool? windowcell = false) {

            Gtk.CssProvider css_provider;
            string gridcell_css = """
            .windowbutton {
                border-radius: 0px;
                margin: 0px;
                box-shadow: none;
                background-color: rgb(0, 100, 148);
                min-width: 4px;
            }
            .bgbutton {
                background-color: rgb(210, 210, 210);
                border-radius: 0px;
                margin: 0px;
                box-shadow: none;
                min-width: 4px;
            }
            """;
            this.set_sensitive(false);
            Gdk.Screen gdk_scr = Gdk.Screen.get_default();
            css_provider = new Gtk.CssProvider();
            try {
                css_provider.load_from_data(gridcell_css);
                Gtk.StyleContext.add_provider_for_screen(
                    gdk_scr, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
                );
            }
            catch (Error e) {
                stderr.printf ("%s\n", e.message);
            }
            if (windowcell) {
                this.get_style_context().add_class("windowbutton");
            }
            else {
                this.get_style_context().add_class("bgbutton");
            }
        }
    }

    private class ShowShufflerGrid : Gtk.Grid {
        /*
        With the grid (cols/rows), the grid-position of the window subject
        (gridx/gridy) and the window span (xspan/yspan, in units of grid
        cells) as arguments, this class produces the grid, representing
        the window on grid.
        Optional (but positional) additional arguments:
        grid-xsize (px)/grid-ysize(px) of the displayed representation.
        The last two arguments can be used to show alternative size/pro-
        portions from a rotated screen.
        */
        private bool string_inlist (string lookfor, string[] arr) {
            for (int i=0; i < arr.length; i++) {
                if (lookfor == arr[i]) {
                    return true;
                }
            }
            return false;
        }

        public ShowShufflerGrid(
            int cols, int rows, int gridx, int gridy, int xspan, int yspan,
            int gridsize_x = 350, int gridsize_y = 200
        ) {
            int cellunit_hor = (int)((float)gridsize_x/(float)cols);
            int cellunit_vert = (int)((float)gridsize_y/(float)rows);
            // now get cells representing the window (wincells)
            // - cell range of window representing cells x/y
            int[] xrange = {};
            for (int i=gridx;i<gridx+xspan; i++) {
                xrange += i;
            }
            int[] yrange = {};
            for (int i=gridy;i<gridy+yspan; i++) {
                yrange += i;
            }
            // - coords of window representing cell
            string[] wincells = {};
            foreach (int x in xrange) {
                foreach (int y in yrange) {
                    wincells += @"$x|$y";
                }
            }
            // now get cells representing the background (wincells)
            // - get all cells, check if they belong to the window
            //   representation
            for (int c=0; c<cols; c++) {
                for (int r=0;r<rows;r++) {
                    string coords = @"$c|$r";
                    print(@"$coords\n");
                    bool fromwindow = false;
                    if (string_inlist(coords, wincells)) {
                        fromwindow = true;
                    }
                    Button newbutton = new GridDisplayButton(fromwindow);
                    newbutton.set_size_request(cellunit_hor, cellunit_vert);
                    this.attach(newbutton, c, r, 1, 1);
                }
            }
            this.show_all();
        }
    }
}