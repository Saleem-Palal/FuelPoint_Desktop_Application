package fdx.remote.plus;

import adr.stringfunctions.stringfunctions;
import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.os.Build;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import anywheresoftware.b4a.B4AActivity;
import anywheresoftware.b4a.B4AMenuItem;
import anywheresoftware.b4a.BA;
import anywheresoftware.b4a.BALayout;
import anywheresoftware.b4a.Msgbox;
import anywheresoftware.b4a.agraham.dialogs.InputDialog;
import anywheresoftware.b4a.keywords.Common;
import anywheresoftware.b4a.keywords.DateTime;
import anywheresoftware.b4a.keywords.constants.Colors;
import anywheresoftware.b4a.keywords.constants.DialogResponse;
import anywheresoftware.b4a.objects.ActivityWrapper;
import anywheresoftware.b4a.objects.ButtonWrapper;
import anywheresoftware.b4a.objects.EditTextWrapper;
import anywheresoftware.b4a.objects.ImageViewWrapper;
import anywheresoftware.b4a.objects.LabelWrapper;
import anywheresoftware.b4a.objects.ListViewWrapper;
import anywheresoftware.b4a.objects.PanelWrapper;
import anywheresoftware.b4a.objects.ServiceHelper;
import anywheresoftware.b4a.objects.SocketWrapper;
import anywheresoftware.b4a.objects.ViewWrapper;
import anywheresoftware.b4a.objects.streams.File;
import anywheresoftware.b4a.phone.Phone;
import anywheresoftware.b4a.randomaccessfile.AsyncStreams;
import java.lang.ref.WeakReference;
import java.util.ArrayList;

/* JADX INFO: loaded from: classes.dex */
public class main extends Activity implements B4AActivity {
    public static long _adjustpassword = 0;
    public static AsyncStreams _astreams = null;
    public static long _datepassword = 0;
    public static long _idpassword = 0;
    public static long _lcdviewpassword = 0;
    public static int _ln = 0;
    public static String _msg = "";
    public static boolean _printercolumn = false;
    public static long _ratepassword = 0;
    public static boolean _saleevents = false;
    public static long _slowhidepassword = 0;
    public static SocketWrapper _socket1 = null;
    public static int _sp = 0;
    public static int _st = 0;
    public static String _strassemblysetting = "";
    public static String _strcorrectionsetting = "";
    public static String _strdate = "";
    public static String _strday = "";
    public static String _strhidepulses = "";
    public static String _strhrs = "";
    public static String _strlcdview = "";
    public static String _strliter = "";
    public static String _strmin = "";
    public static String _strmonth = "";
    public static String _strprice = "";
    public static String _strproductid = "";
    public static String _strpulsesetting = "";
    public static String _strrate = "";
    public static String _strsec = "";
    public static String _strslowflow = "";
    public static String _strtime = "";
    public static String _strtotal = "";
    public static String _strtotalmeter = "";
    public static String _strunitid = "";
    public static String _stryear = "";
    public static long _timepassword = 0;
    public static long _totalpassword = 0;
    public static Phone.PhoneWakeState _ws = null;
    public static String _x = "";
    static boolean afterFirstLayout = false;
    public static boolean dontPause = false;
    public static final boolean fullScreen = true;
    public static final boolean includeTitle = false;
    static boolean isFirst = true;
    public static main mostCurrent = null;
    public static WeakReference<Activity> previousOne = null;
    public static BA processBA = null;
    private static boolean processGlobalsRun = false;
    ActivityWrapper _activity;
    BA activityBA;
    BALayout layout;
    ArrayList<B4AMenuItem> menuItems;
    private Boolean onKeySubExist = null;
    private Boolean onKeyUpSubExist = null;
    public Common __c = null;
    public stringfunctions _sf = null;
    public EditTextWrapper _edittext2 = null;
    public LabelWrapper _lblrx = null;
    public LabelWrapper _lblrx2 = null;
    public PanelWrapper _pidle = null;
    public LabelWrapper _lblunitid = null;
    public LabelWrapper _lblproduct = null;
    public LabelWrapper _lbldisplayliter = null;
    public LabelWrapper _lbldisplayprice = null;
    public LabelWrapper _lbldisplayrate = null;
    public ImageViewWrapper _imgnzl = null;
    public LabelWrapper _lblpreset = null;
    public LabelWrapper _lbltotalmeter = null;
    public ButtonWrapper _btnsales = null;
    public ListViewWrapper _lstsales = null;
    public PanelWrapper _pnlsales = null;
    public PanelWrapper _pnlsetting = null;
    public ButtonWrapper _btnlog = null;
    public PanelWrapper _pnllog = null;
    public ButtonWrapper _btnsettings = null;
    public EditTextWrapper _edittext1 = null;
    public LabelWrapper _lblrate = null;
    public LabelWrapper _lbltotal = null;
    public LabelWrapper _lblslowflow = null;
    public LabelWrapper _lblhide = null;
    public LabelWrapper _lblkeyboarddisplay = null;
    public LabelWrapper _lblassembly = null;
    public LabelWrapper _lblcorrection = null;
    public LabelWrapper _lbldate = null;
    public LabelWrapper _lbltime = null;
    public ButtonWrapper _btnupdatesettings = null;
    public ButtonWrapper _btnrate = null;
    public ButtonWrapper _btntotal = null;
    public ButtonWrapper _btnslowflow = null;
    public ButtonWrapper _btnhide = null;
    public ButtonWrapper _btnkeyboarddisplay = null;
    public ButtonWrapper _btnassembly = null;
    public ButtonWrapper _btncorrection = null;
    public ButtonWrapper _btndate = null;
    public ButtonWrapper _btntime = null;
    public ButtonWrapper _btnprinter = null;
    public LabelWrapper _lblsystemparameter = null;
    public PanelWrapper _pnlfilling = null;
    public ButtonWrapper _btnback = null;
    public EditTextWrapper _txtlog = null;
    public ButtonWrapper _btnprinter1 = null;
    public ButtonWrapper _btnprinter2 = null;
    public ButtonWrapper _btnprinter3 = null;
    public ButtonWrapper _btnprinter4 = null;
    public ButtonWrapper _btnprinter5 = null;
    public ButtonWrapper _btnprinter6 = null;
    public ButtonWrapper _btnprinter7 = null;
    public ButtonWrapper _btnprinter8 = null;
    public EditTextWrapper _txtprinter1 = null;
    public EditTextWrapper _txtprinter2 = null;
    public EditTextWrapper _txtprinter3 = null;
    public EditTextWrapper _txtprinter4 = null;
    public EditTextWrapper _txtprinter5 = null;
    public EditTextWrapper _txtprinter6 = null;
    public EditTextWrapper _txtprinter7 = null;
    public EditTextWrapper _txtprinter8 = null;
    public LabelWrapper _lblprintlen1 = null;
    public LabelWrapper _lblprintlen2 = null;
    public LabelWrapper _lblprintlen3 = null;
    public LabelWrapper _lblprintlen4 = null;
    public LabelWrapper _lblprintlen5 = null;
    public LabelWrapper _lblprintlen6 = null;
    public LabelWrapper _lblprintlen7 = null;
    public LabelWrapper _lblprintlen8 = null;
    public ButtonWrapper _btn9600 = null;
    public ButtonWrapper _btn115200 = null;
    public ButtonWrapper _btn32col = null;
    public ButtonWrapper _btn40col = null;
    public LabelWrapper _label10 = null;
    public PanelWrapper _pnlprinter = null;
    public ButtonWrapper _btnprinterback = null;
    public PanelWrapper _pnllogo = null;
    public PanelWrapper _pnlbackground = null;
    public LabelWrapper _lblslowfast = null;
    public ButtonWrapper _btnslowfast = null;
    public LabelWrapper _label9 = null;

    public static String _activity_resume() throws Exception {
        return "";
    }

    public static String _clearprintertext() throws Exception {
        return "";
    }

    @Override // android.app.Activity
    public void onCreate(Bundle bundle) {
        Activity activity;
        super.onCreate(bundle);
        mostCurrent = this;
        if (processBA == null) {
            BA ba = new BA(getApplicationContext(), (BALayout) null, (BA) null, "fdx.remote.plus", "fdx.remote.plus.main");
            processBA = ba;
            ba.loadHtSubs(getClass());
            BALayout.setDeviceScale(getApplicationContext().getResources().getDisplayMetrics().density);
        } else {
            WeakReference<Activity> weakReference = previousOne;
            if (weakReference != null && (activity = weakReference.get()) != null && activity != this) {
                BA.LogInfo("Killing previous instance (main).");
                activity.finish();
            }
        }
        processBA.setActivityPaused(true);
        processBA.runHook("oncreate", this, null);
        getWindow().requestFeature(1);
        getWindow().setFlags(1024, 1024);
        processBA.sharedProcessBA.activityBA = null;
        BALayout bALayout = new BALayout(this);
        this.layout = bALayout;
        setContentView(bALayout);
        afterFirstLayout = false;
        WaitForLayout waitForLayout = new WaitForLayout();
        if (ServiceHelper.StarterHelper.startFromActivity(this, processBA, waitForLayout, true)) {
            BA.handler.postDelayed(waitForLayout, 5L);
        }
    }

    static class WaitForLayout implements Runnable {
        WaitForLayout() {
        }

        @Override // java.lang.Runnable
        public void run() {
            if (main.afterFirstLayout || main.mostCurrent == null) {
                return;
            }
            if (main.mostCurrent.layout.getWidth() == 0) {
                BA.handler.postDelayed(this, 5L);
                return;
            }
            main.mostCurrent.layout.getLayoutParams().height = main.mostCurrent.layout.getHeight();
            main.mostCurrent.layout.getLayoutParams().width = main.mostCurrent.layout.getWidth();
            main.afterFirstLayout = true;
            main.mostCurrent.afterFirstLayout();
        }
    }

    /* JADX INFO: Access modifiers changed from: private */
    public void afterFirstLayout() {
        if (this != mostCurrent) {
            return;
        }
        this.activityBA = new BA(this, this.layout, processBA, "fdx.remote.plus", "fdx.remote.plus.main");
        processBA.sharedProcessBA.activityBA = new WeakReference<>(this.activityBA);
        ViewWrapper.lastId = 0;
        this._activity = new ActivityWrapper(this.activityBA, "activity");
        Msgbox.isDismissing = false;
        if (BA.isShellModeRuntimeCheck(processBA)) {
            if (isFirst) {
                processBA.raiseEvent2(null, true, "SHELL", false, new Object[0]);
            }
            BA ba = processBA;
            ba.raiseEvent2(null, true, "CREATE", true, "fdx.remote.plus.main", ba, this.activityBA, this._activity, Float.valueOf(Common.Density), mostCurrent);
            this._activity.reinitializeForShell(this.activityBA, "activity");
        }
        initializeProcessGlobals();
        initializeGlobals();
        StringBuilder sb = new StringBuilder();
        sb.append("** Activity (main) Create ");
        sb.append(isFirst ? "(first time)" : "");
        sb.append(" **");
        BA.LogInfo(sb.toString());
        processBA.raiseEvent2(null, true, "activity_create", false, Boolean.valueOf(isFirst));
        isFirst = false;
        if (this != mostCurrent) {
            return;
        }
        processBA.setActivityPaused(false);
        BA.LogInfo("** Activity (main) Resume **");
        processBA.raiseEvent(null, "activity_resume", new Object[0]);
        if (Build.VERSION.SDK_INT >= 11) {
            try {
                Activity.class.getMethod("invalidateOptionsMenu", new Class[0]).invoke(this, null);
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    @Override // anywheresoftware.b4a.B4AActivity
    public void addMenuItem(B4AMenuItem b4AMenuItem) {
        if (this.menuItems == null) {
            this.menuItems = new ArrayList<>();
        }
        this.menuItems.add(b4AMenuItem);
    }

    @Override // android.app.Activity
    public boolean onCreateOptionsMenu(Menu menu) {
        super.onCreateOptionsMenu(menu);
        try {
            if (processBA.subExists("activity_actionbarhomeclick")) {
                Class.forName("android.app.ActionBar").getMethod("setHomeButtonEnabled", Boolean.TYPE).invoke(getClass().getMethod("getActionBar", new Class[0]).invoke(this, new Object[0]), true);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        if (processBA.runHook("oncreateoptionsmenu", this, new Object[]{menu})) {
            return true;
        }
        ArrayList<B4AMenuItem> arrayList = this.menuItems;
        if (arrayList == null) {
            return false;
        }
        for (B4AMenuItem b4AMenuItem : arrayList) {
            MenuItem menuItemAdd = menu.add(b4AMenuItem.title);
            if (b4AMenuItem.drawable != null) {
                menuItemAdd.setIcon(b4AMenuItem.drawable);
            }
            if (Build.VERSION.SDK_INT >= 11) {
                try {
                    if (b4AMenuItem.addToBar) {
                        MenuItem.class.getMethod("setShowAsAction", Integer.TYPE).invoke(menuItemAdd, 1);
                    }
                } catch (Exception e2) {
                    e2.printStackTrace();
                }
            }
            menuItemAdd.setOnMenuItemClickListener(new B4AMenuItemsClickListener(b4AMenuItem.eventName.toLowerCase(BA.cul)));
        }
        return true;
    }

    @Override // android.app.Activity
    public boolean onOptionsItemSelected(MenuItem menuItem) {
        if (menuItem.getItemId() == 16908332) {
            processBA.raiseEvent(null, "activity_actionbarhomeclick", new Object[0]);
            return true;
        }
        return super.onOptionsItemSelected(menuItem);
    }

    @Override // android.app.Activity
    public boolean onPrepareOptionsMenu(Menu menu) {
        super.onPrepareOptionsMenu(menu);
        processBA.runHook("onprepareoptionsmenu", this, new Object[]{menu});
        return true;
    }

    @Override // android.app.Activity
    protected void onStart() {
        super.onStart();
        processBA.runHook("onstart", this, null);
    }

    @Override // android.app.Activity
    protected void onStop() {
        super.onStop();
        processBA.runHook("onstop", this, null);
    }

    @Override // android.app.Activity, android.view.Window.Callback
    public void onWindowFocusChanged(boolean z) {
        super.onWindowFocusChanged(z);
        if (processBA.subExists("activity_windowfocuschanged")) {
            processBA.raiseEvent2(null, true, "activity_windowfocuschanged", false, Boolean.valueOf(z));
        }
    }

    private class B4AMenuItemsClickListener implements MenuItem.OnMenuItemClickListener {
        private final String eventName;

        public B4AMenuItemsClickListener(String str) {
            this.eventName = str;
        }

        @Override // android.view.MenuItem.OnMenuItemClickListener
        public boolean onMenuItemClick(MenuItem menuItem) {
            main.processBA.raiseEventFromUI(menuItem.getTitle(), this.eventName + "_click", new Object[0]);
            return true;
        }
    }

    public static Class<?> getObject() {
        return main.class;
    }

    @Override // android.app.Activity, android.view.KeyEvent.Callback
    public boolean onKeyDown(int i, KeyEvent keyEvent) {
        if (processBA.runHook("onkeydown", this, new Object[]{Integer.valueOf(i), keyEvent})) {
            return true;
        }
        if (this.onKeySubExist == null) {
            this.onKeySubExist = Boolean.valueOf(processBA.subExists("activity_keypress"));
        }
        if (this.onKeySubExist.booleanValue()) {
            if (i == 4 && Build.VERSION.SDK_INT >= 18) {
                HandleKeyDelayed handleKeyDelayed = new HandleKeyDelayed();
                handleKeyDelayed.kc = i;
                BA.handler.post(handleKeyDelayed);
                return true;
            }
            if (new HandleKeyDelayed().runDirectly(i)) {
                return true;
            }
        }
        return super.onKeyDown(i, keyEvent);
    }

    private class HandleKeyDelayed implements Runnable {
        int kc;

        private HandleKeyDelayed() {
        }

        @Override // java.lang.Runnable
        public void run() {
            runDirectly(this.kc);
        }

        public boolean runDirectly(int i) {
            Boolean bool = (Boolean) main.processBA.raiseEvent2(main.this._activity, false, "activity_keypress", false, Integer.valueOf(i));
            if (bool == null || bool.booleanValue()) {
                return true;
            }
            if (i != 4) {
                return false;
            }
            main.this.finish();
            return true;
        }
    }

    @Override // android.app.Activity, android.view.KeyEvent.Callback
    public boolean onKeyUp(int i, KeyEvent keyEvent) {
        Boolean bool;
        if (processBA.runHook("onkeyup", this, new Object[]{Integer.valueOf(i), keyEvent})) {
            return true;
        }
        if (this.onKeyUpSubExist == null) {
            this.onKeyUpSubExist = Boolean.valueOf(processBA.subExists("activity_keyup"));
        }
        if (this.onKeyUpSubExist.booleanValue() && ((bool = (Boolean) processBA.raiseEvent2(this._activity, false, "activity_keyup", false, Integer.valueOf(i))) == null || bool.booleanValue())) {
            return true;
        }
        return super.onKeyUp(i, keyEvent);
    }

    @Override // android.app.Activity
    public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        processBA.runHook("onnewintent", this, new Object[]{intent});
    }

    @Override // android.app.Activity
    public void onPause() {
        super.onPause();
        if (this._activity != null && this == mostCurrent) {
            Msgbox.dismiss(true);
            if (!dontPause) {
                BA.LogInfo("** Activity (main) Pause, UserClosed = " + this.activityBA.activity.isFinishing() + " **");
            } else {
                BA.LogInfo("** Activity (main) Pause event (activity is not paused). **");
            }
            if (mostCurrent != null) {
                processBA.raiseEvent2(this._activity, true, "activity_pause", false, Boolean.valueOf(this.activityBA.activity.isFinishing()));
            }
            if (!dontPause) {
                processBA.setActivityPaused(true);
                mostCurrent = null;
            }
            if (!this.activityBA.activity.isFinishing()) {
                previousOne = new WeakReference<>(this);
            }
            Msgbox.isDismissing = false;
            processBA.runHook("onpause", this, null);
        }
    }

    @Override // android.app.Activity
    public void onDestroy() {
        super.onDestroy();
        previousOne = null;
        processBA.runHook("ondestroy", this, null);
    }

    @Override // android.app.Activity
    public void onResume() {
        super.onResume();
        mostCurrent = this;
        Msgbox.isDismissing = false;
        if (this.activityBA != null) {
            BA.handler.post(new ResumeMessage(mostCurrent));
        }
        processBA.runHook("onresume", this, null);
    }

    private static class ResumeMessage implements Runnable {
        private final WeakReference<Activity> activity;

        public ResumeMessage(Activity activity) {
            this.activity = new WeakReference<>(activity);
        }

        @Override // java.lang.Runnable
        public void run() {
            main mainVar = main.mostCurrent;
            if (mainVar == null || mainVar != this.activity.get()) {
                return;
            }
            main.processBA.setActivityPaused(false);
            BA.LogInfo("** Activity (main) Resume **");
            if (mainVar != main.mostCurrent) {
                return;
            }
            main.processBA.raiseEvent(mainVar._activity, "activity_resume", null);
        }
    }

    @Override // android.app.Activity
    protected void onActivityResult(int i, int i2, Intent intent) {
        processBA.onActivityResult(i, i2, intent);
        processBA.runHook("onactivityresult", this, new Object[]{Integer.valueOf(i), Integer.valueOf(i2)});
    }

    private static void initializeGlobals() {
        processBA.raiseEvent2(null, true, "globals", false, null);
    }

    @Override // android.app.Activity
    public void onRequestPermissionsResult(int i, String[] strArr, int[] iArr) {
        for (int i2 = 0; i2 < strArr.length; i2++) {
            Object[] objArr = new Object[2];
            objArr[0] = strArr[i2];
            objArr[1] = Boolean.valueOf(iArr[i2] == 0);
            processBA.raiseEventFromDifferentThread(null, null, 0, "activity_permissionresult", true, objArr);
        }
    }

    public static boolean isAnyActivityVisible() {
        return (mostCurrent != null) | false;
    }

    public static String _activity_create(boolean z) throws Exception {
        mostCurrent._sf._initialize(processBA);
        if (!z) {
            return "";
        }
        Phone.PhoneWakeState.KeepAlive(processBA, true);
        main mainVar = mostCurrent;
        mainVar._activity.LoadLayout("1", mainVar.activityBA);
        mostCurrent._pnlsales.setVisible(false);
        mostCurrent._pnlfilling.setVisible(false);
        mostCurrent._pnllog.setVisible(false);
        mostCurrent._pnlbackground.setVisible(false);
        mostCurrent._pnllogo.BringToFront();
        mostCurrent._pnllogo.setVisible(true);
        _delay(4000L);
        mostCurrent._pnllogo.setVisible(false);
        _socket1.Initialize("Socket1");
        _socket1.Connect(processBA, "192.168.5.1", 9876, 15000);
        mostCurrent._pnlbackground.setVisible(true);
        mostCurrent._pnlfilling.setVisible(true);
        mostCurrent._pnlfilling.BringToFront();
        mostCurrent._pnllog.setVisible(true);
        mostCurrent._pnllog.BringToFront();
        mostCurrent._txtlog.setInputType(0);
        mostCurrent._txtlog.setSingleLine(false);
        return "";
    }

    public static String _activity_pause(boolean z) throws Exception {
        if (!z) {
            return "";
        }
        Common.LogImpl("2327682", "closing", 0);
        _astreams.Close();
        _socket1.Close();
        return "";
    }

    public static String _astreams_error() throws Exception {
        Common.ToastMessageShow(BA.ObjectToCharSequence(Common.LastException(mostCurrent.activityBA).getMessage()), true);
        Common.LogImpl("2983042", "AStreams_Error", 0);
        return "";
    }

    public static String _astreams_newdata(byte[] bArr) throws Exception {
        _msg = Common.BytesToString(bArr, 0, bArr.length, "UTF8");
        String str = _x + _msg;
        _x = str;
        if (str.contains(Common.CRLF)) {
            _st = mostCurrent._sf._v7(_x, "<") + 2;
            int i_v7 = mostCurrent._sf._v7(_x, ">") + 1;
            _sp = i_v7;
            int i = i_v7 - _st;
            _ln = i;
            if (i > 1 && !mostCurrent._lblrx.getText().equals(mostCurrent._sf._vvvv5(_x, _st, _ln))) {
                main mainVar = mostCurrent;
                mainVar._lblrx.setText(BA.ObjectToCharSequence(mainVar._sf._vvvv5(_x, _st, _ln)));
                if (_ln == 33) {
                    _decode_33();
                }
                if (_ln == 42) {
                    _decode_42();
                }
                if (_ln == 36) {
                    _decode_36();
                }
                if (_ln == 52) {
                    _decode_52();
                }
                if (_ln == 29) {
                    _decode_29();
                }
                if (_ln == 37) {
                    _decode_37();
                }
                if (_ln == 43) {
                    _decode_43();
                }
                if (_ln == 3) {
                    _decode_3();
                }
            }
            _x = "";
        }
        return "";
    }

    public static String _astreams_terminated() throws Exception {
        Common.LogImpl("21048577", "AStreams_Terminated", 0);
        return "";
    }

    public static String _btn115200_click() throws Exception {
        _astreams.Write(("<B1>" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
        _astreams.Write(("<QP>" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        return "";
    }

    public static String _btn32col_click() throws Exception {
        _astreams.Write(("<C3>" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
        _astreams.Write(("<QP>" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        return "";
    }

    public static String _btn40col_click() throws Exception {
        _astreams.Write(("<C4>" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
        _astreams.Write(("<QP>" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        return "";
    }

    public static String _btn9600_click() throws Exception {
        _astreams.Write(("<B9>" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
        _astreams.Write(("<QP>" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        return "";
    }

    public static String _btnassembly_click() throws Exception {
        InputDialog inputDialog = new InputDialog();
        InputDialog.NumberDialog numberDialog = new InputDialog.NumberDialog();
        try {
            inputDialog.setHint("Enter Password");
            inputDialog.setInputType(2);
            inputDialog.setPasswordMode(true);
            BA ba = mostCurrent.activityBA;
            Bitmap bitmap = (Bitmap) Common.Null;
            inputDialog.Show("Enter Code For Assembly Setting", "Enter Password", "OK", "", "", ba, bitmap);
            if (((long) Double.parseDouble(inputDialog.getInput())) == _adjustpassword) {
                Double.parseDouble(_strassemblysetting);
                numberDialog.setShowSign(true);
                numberDialog.setDecimal(0);
                numberDialog.setDigits(3);
                long j = 100;
                numberDialog.setNumber((int) (((long) Double.parseDouble(_strassemblysetting)) - 100));
                BA ba2 = mostCurrent.activityBA;
                Bitmap bitmap2 = (Bitmap) Common.Null;
                numberDialog.Show("New Value", "OK", "Cancel", "", ba2, bitmap2);
                long number = numberDialog.getNumber();
                if (numberDialog.getResponse() != -1) {
                    return "";
                }
                if (number <= 0) {
                    if (number != 0) {
                        j = number < 0 ? 100 + number : number;
                    }
                }
                _astreams.Write(("<AS" + _convertstring((int) j) + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
                Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
                StringBuilder sb = new StringBuilder();
                sb.append("<QR>");
                sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
                _astreams.Write(sb.toString().getBytes("UTF8"));
                return "";
            }
            Common.Msgbox(BA.ObjectToCharSequence("Wrong Password"), BA.ObjectToCharSequence("Error"), mostCurrent.activityBA);
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _btnback_click() throws Exception {
        mostCurrent._pnlsetting.setVisible(false);
        mostCurrent._pnlfilling.setVisible(true);
        mostCurrent._pnlfilling.BringToFront();
        mostCurrent._pnllog.setVisible(true);
        mostCurrent._pnllog.BringToFront();
        mostCurrent._btnrate.setEnabled(false);
        mostCurrent._btntotal.setEnabled(false);
        mostCurrent._btnslowflow.setEnabled(false);
        mostCurrent._btnslowfast.setEnabled(false);
        mostCurrent._btnhide.setEnabled(false);
        mostCurrent._btnkeyboarddisplay.setEnabled(false);
        mostCurrent._btnassembly.setEnabled(false);
        mostCurrent._btncorrection.setEnabled(false);
        mostCurrent._btndate.setEnabled(false);
        mostCurrent._btntime.setEnabled(false);
        mostCurrent._btnprinter.setEnabled(false);
        mostCurrent._btnsettings.setEnabled(true);
        mostCurrent._btnsales.setEnabled(true);
        mostCurrent._btnlog.setEnabled(true);
        return "";
    }

    public static String _btncorrection_click() throws Exception {
        InputDialog inputDialog = new InputDialog();
        InputDialog.NumberDialog numberDialog = new InputDialog.NumberDialog();
        try {
            inputDialog.setHint("Enter Password");
            inputDialog.setInputType(2);
            inputDialog.setPasswordMode(true);
            BA ba = mostCurrent.activityBA;
            Bitmap bitmap = (Bitmap) Common.Null;
            inputDialog.Show("Enter Code For Corection Setting", "Enter Password", "OK", "", "", ba, bitmap);
            if (((long) Double.parseDouble(inputDialog.getInput())) == _adjustpassword) {
                Double.parseDouble(_strcorrectionsetting);
                numberDialog.setShowSign(true);
                numberDialog.setDecimal(0);
                numberDialog.setDigits(3);
                long j = 100;
                numberDialog.setNumber((int) (((long) Double.parseDouble(_strcorrectionsetting)) - 100));
                BA ba2 = mostCurrent.activityBA;
                Bitmap bitmap2 = (Bitmap) Common.Null;
                numberDialog.Show("New Value", "OK", "Cancel", "", ba2, bitmap2);
                long number = numberDialog.getNumber();
                if (numberDialog.getResponse() != -1) {
                    return "";
                }
                if (number <= 0) {
                    if (number != 0) {
                        j = number < 0 ? 100 + number : number;
                    }
                }
                _astreams.Write(("<PS" + _convertstring((int) j) + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
                Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
                StringBuilder sb = new StringBuilder();
                sb.append("<QR>");
                sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
                _astreams.Write(sb.toString().getBytes("UTF8"));
                return "";
            }
            Common.Msgbox(BA.ObjectToCharSequence("Wrong Password"), BA.ObjectToCharSequence("Error"), mostCurrent.activityBA);
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _btndate_click() throws Exception {
        InputDialog inputDialog = new InputDialog();
        InputDialog.DateDialog dateDialog = new InputDialog.DateDialog();
        try {
            inputDialog.setHint("Enter Password");
            inputDialog.setInputType(2);
            inputDialog.setPasswordMode(true);
            BA ba = mostCurrent.activityBA;
            Bitmap bitmap = (Bitmap) Common.Null;
            inputDialog.Show("Enter Code For Date Setting", "Enter Password", "OK", "", "", ba, bitmap);
            if (((long) Double.parseDouble(inputDialog.getInput())) == _datepassword) {
                dateDialog.setYear((int) (Double.parseDouble(_stryear) + 2000.0d));
                dateDialog.setMonth((int) Double.parseDouble(_strmonth));
                dateDialog.setDayOfMonth((int) Double.parseDouble(_strday));
                BA ba2 = mostCurrent.activityBA;
                Bitmap bitmap2 = (Bitmap) Common.Null;
                dateDialog.Show("Set date", "Date", "OK", "Cancel", "", ba2, bitmap2);
                if (dateDialog.getResponse() != -1) {
                    return "";
                }
                if (dateDialog.getYear() > 2000) {
                    _stryear = BA.NumberToString(dateDialog.getYear() - 2000);
                } else {
                    Common.Msgbox(BA.ObjectToCharSequence("Error in Year value"), BA.ObjectToCharSequence("Error"), mostCurrent.activityBA);
                }
                if (dateDialog.getMonth() < 10) {
                    _strmonth = "0" + BA.NumberToString(dateDialog.getMonth());
                } else {
                    _strmonth = BA.NumberToString(dateDialog.getMonth());
                }
                if (dateDialog.getDayOfMonth() < 10) {
                    _strday = "0" + BA.NumberToString(dateDialog.getDayOfMonth());
                } else {
                    _strday = BA.NumberToString(dateDialog.getDayOfMonth());
                }
                _astreams.Write(("<DS" + _convertstring((int) Double.parseDouble(_strday + _strmonth + _stryear)) + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
                Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
                StringBuilder sb = new StringBuilder();
                sb.append("<QR>");
                sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
                _astreams.Write(sb.toString().getBytes("UTF8"));
                return "";
            }
            Common.Msgbox(BA.ObjectToCharSequence("Wrong Password"), BA.ObjectToCharSequence("Error"), mostCurrent.activityBA);
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _btnhide_click() throws Exception {
        InputDialog inputDialog = new InputDialog();
        InputDialog.NumberDialog numberDialog = new InputDialog.NumberDialog();
        try {
            inputDialog.setHint("Enter Password");
            inputDialog.setInputType(2);
            inputDialog.setPasswordMode(true);
            BA ba = mostCurrent.activityBA;
            Bitmap bitmap = (Bitmap) Common.Null;
            inputDialog.Show("Enter Code For Hide Pulses Setting", "Enter Password", "OK", "", "", ba, bitmap);
            if (((long) Double.parseDouble(inputDialog.getInput())) == _slowhidepassword) {
                numberDialog.setShowSign(false);
                numberDialog.setDecimal(0);
                numberDialog.setDigits(1);
                numberDialog.setNumber((int) Double.parseDouble(mostCurrent._lblhide.getText()));
                BA ba2 = mostCurrent.activityBA;
                Bitmap bitmap2 = (Bitmap) Common.Null;
                numberDialog.Show("New Value", "OK", "Cancel", "", ba2, bitmap2);
                long number = numberDialog.getNumber();
                if (numberDialog.getResponse() == -1) {
                    _astreams.Write(("<HP" + _convertstring((int) number) + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
                    Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
                    StringBuilder sb = new StringBuilder();
                    sb.append("<QR>");
                    sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
                    _astreams.Write(sb.toString().getBytes("UTF8"));
                }
            } else {
                Common.Msgbox(BA.ObjectToCharSequence("Wrong Password"), BA.ObjectToCharSequence("Error"), mostCurrent.activityBA);
            }
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _btnkeyboarddisplay_click() throws Exception {
        InputDialog inputDialog = new InputDialog();
        InputDialog.NumberDialog numberDialog = new InputDialog.NumberDialog();
        try {
            inputDialog.setHint("Enter Password");
            inputDialog.setInputType(2);
            inputDialog.setPasswordMode(true);
            BA ba = mostCurrent.activityBA;
            Bitmap bitmap = (Bitmap) Common.Null;
            inputDialog.Show("Enter Code For Preset Display Style", "Enter Password", "OK", "", "", ba, bitmap);
            if (((long) Double.parseDouble(inputDialog.getInput())) == _lcdviewpassword) {
                numberDialog.setShowSign(false);
                numberDialog.setDecimal(0);
                numberDialog.setDigits(1);
                BA ba2 = mostCurrent.activityBA;
                Bitmap bitmap2 = (Bitmap) Common.Null;
                numberDialog.Show("New Value (0,1,2)", "OK", "Cancel", "", ba2, bitmap2);
                long number = numberDialog.getNumber();
                if (numberDialog.getResponse() == -1) {
                    if (number > 2) {
                        Common.Msgbox(BA.ObjectToCharSequence("Out Of Range, Please Enter Between 0-2"), BA.ObjectToCharSequence("Error"), mostCurrent.activityBA);
                    } else {
                        _astreams.Write(("<LV" + _convertstring((int) number) + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
                        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
                        StringBuilder sb = new StringBuilder();
                        sb.append("<QR>");
                        sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
                        _astreams.Write(sb.toString().getBytes("UTF8"));
                    }
                }
            } else {
                Common.Msgbox(BA.ObjectToCharSequence("Wrong Password"), BA.ObjectToCharSequence("Error"), mostCurrent.activityBA);
            }
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _btnlog_click() throws Exception {
        Integer numValueOf = Integer.valueOf(Common.Msgbox2(BA.ObjectToCharSequence("Do you really want to exit"), BA.ObjectToCharSequence("Exit Application"), "Yes", "", "No", (Bitmap) Common.Null, mostCurrent.activityBA));
        DialogResponse dialogResponse = Common.DialogResponse;
        DialogResponse dialogResponse2 = Common.DialogResponse;
        DialogResponse dialogResponse3 = Common.DialogResponse;
        if (BA.switchObjectToInt(numValueOf, -1, -3, -2) != 0) {
            return "";
        }
        mostCurrent._activity.Finish();
        Common.ExitApplication();
        return "";
    }

    public static String _btnprinter_click() throws Exception {
        mostCurrent._txtprinter1.setText(BA.ObjectToCharSequence(""));
        mostCurrent._txtprinter2.setText(BA.ObjectToCharSequence(""));
        mostCurrent._txtprinter3.setText(BA.ObjectToCharSequence(""));
        mostCurrent._txtprinter4.setText(BA.ObjectToCharSequence(""));
        mostCurrent._txtprinter5.setText(BA.ObjectToCharSequence(""));
        mostCurrent._txtprinter6.setText(BA.ObjectToCharSequence(""));
        mostCurrent._txtprinter7.setText(BA.ObjectToCharSequence(""));
        mostCurrent._txtprinter8.setText(BA.ObjectToCharSequence(""));
        _astreams.Write(("<QP>" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        mostCurrent._pnlprinter.setVisible(true);
        mostCurrent._pnlprinter.BringToFront();
        return "";
    }

    public static String _btnprinter1_click() throws Exception {
        _clearprintertext();
        String text = mostCurrent._txtprinter1.getText();
        if (mostCurrent._sf._vvv7(text) < 20) {
            text = mostCurrent._sf._vvvvv4(text, " ", 20, true);
        }
        _astreams.Write(("<L1" + text + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
        StringBuilder sb = new StringBuilder();
        sb.append("<QP>");
        sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
        _astreams.Write(sb.toString().getBytes("UTF8"));
        return "";
    }

    public static String _btnprinter2_click() throws Exception {
        _clearprintertext();
        String text = mostCurrent._txtprinter2.getText();
        if (mostCurrent._sf._vvv7(text) < 20) {
            text = mostCurrent._sf._vvvvv4(text, " ", 20, true);
        }
        _astreams.Write(("<L2" + text + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
        StringBuilder sb = new StringBuilder();
        sb.append("<QP>");
        sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
        _astreams.Write(sb.toString().getBytes("UTF8"));
        return "";
    }

    public static String _btnprinter3_click() throws Exception {
        _clearprintertext();
        String text = mostCurrent._txtprinter3.getText();
        if (mostCurrent._sf._vvv7(text) < 20) {
            text = mostCurrent._sf._vvvvv4(text, " ", 20, true);
        }
        _astreams.Write(("<L3" + text + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
        StringBuilder sb = new StringBuilder();
        sb.append("<QP>");
        sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
        _astreams.Write(sb.toString().getBytes("UTF8"));
        return "";
    }

    public static String _btnprinter4_click() throws Exception {
        _clearprintertext();
        String text = mostCurrent._txtprinter4.getText();
        if (mostCurrent._sf._vvv7(text) < 20) {
            text = mostCurrent._sf._vvvvv4(text, " ", 20, true);
        }
        _astreams.Write(("<L4" + text + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
        StringBuilder sb = new StringBuilder();
        sb.append("<QP>");
        sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
        _astreams.Write(sb.toString().getBytes("UTF8"));
        return "";
    }

    public static String _btnprinter5_click() throws Exception {
        _clearprintertext();
        String text = mostCurrent._txtprinter5.getText();
        if (mostCurrent._sf._vvv7(text) < 20) {
            text = mostCurrent._sf._vvvvv4(text, " ", 20, true);
        }
        _astreams.Write(("<L5" + text + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
        StringBuilder sb = new StringBuilder();
        sb.append("<QP>");
        sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
        _astreams.Write(sb.toString().getBytes("UTF8"));
        return "";
    }

    public static String _btnprinter6_click() throws Exception {
        _clearprintertext();
        String text = mostCurrent._txtprinter6.getText();
        if (mostCurrent._sf._vvv7(text) < 20) {
            text = mostCurrent._sf._vvvvv4(text, " ", 20, true);
        }
        _astreams.Write(("<L6" + text + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
        StringBuilder sb = new StringBuilder();
        sb.append("<QP>");
        sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
        _astreams.Write(sb.toString().getBytes("UTF8"));
        return "";
    }

    public static String _btnprinter7_click() throws Exception {
        _clearprintertext();
        String text = mostCurrent._txtprinter7.getText();
        if (mostCurrent._sf._vvv7(text) < 20) {
            text = mostCurrent._sf._vvvvv4(text, " ", 20, true);
        }
        _astreams.Write(("<L7" + text + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
        StringBuilder sb = new StringBuilder();
        sb.append("<QP>");
        sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
        _astreams.Write(sb.toString().getBytes("UTF8"));
        return "";
    }

    public static String _btnprinter8_click() throws Exception {
        _clearprintertext();
        String text = mostCurrent._txtprinter8.getText();
        if (mostCurrent._sf._vvv7(text) < 20) {
            text = mostCurrent._sf._vvvvv4(text, " ", 20, true);
        }
        _astreams.Write(("<L8" + text + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
        StringBuilder sb = new StringBuilder();
        sb.append("<QP>");
        sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
        _astreams.Write(sb.toString().getBytes("UTF8"));
        return "";
    }

    public static String _btnprinterback_click() throws Exception {
        mostCurrent._pnlprinter.setVisible(false);
        return "";
    }

    public static String _btnrate_click() throws Exception {
        InputDialog inputDialog = new InputDialog();
        InputDialog.NumberDialog numberDialog = new InputDialog.NumberDialog();
        try {
            inputDialog.setHint("Enter Password");
            inputDialog.setInputType(2);
            inputDialog.setPasswordMode(true);
            BA ba = mostCurrent.activityBA;
            Bitmap bitmap = (Bitmap) Common.Null;
            inputDialog.Show("Enter Code For Rate Setting", "Enter Password", "OK", "", "", ba, bitmap);
            if (((long) Double.parseDouble(inputDialog.getInput())) == _ratepassword) {
                numberDialog.setDecimal(2);
                numberDialog.setShowSign(false);
                numberDialog.setNumber((int) (Double.parseDouble(mostCurrent._lblrate.getText()) * 100.0d));
                BA ba2 = mostCurrent.activityBA;
                Bitmap bitmap2 = (Bitmap) Common.Null;
                numberDialog.Show("New Value", "OK", "Cancel", "", ba2, bitmap2);
                long number = numberDialog.getNumber();
                if (numberDialog.getResponse() == -1) {
                    _astreams.Write(("<RT" + _convertstring((int) number) + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
                    Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
                    StringBuilder sb = new StringBuilder();
                    sb.append("<QR>");
                    sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
                    _astreams.Write(sb.toString().getBytes("UTF8"));
                }
            } else {
                Common.Msgbox(BA.ObjectToCharSequence("Wrong Password"), BA.ObjectToCharSequence("Error"), mostCurrent.activityBA);
            }
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _btnsales_click() throws Exception {
        if (!_saleevents) {
            mostCurrent._lstsales.getSingleLineLayout().Label.setTextSize(11.0f);
            mostCurrent._lstsales.getSingleLineLayout().setItemHeight(Common.DipToCurrent(24));
            LabelWrapper labelWrapper = mostCurrent._lstsales.getSingleLineLayout().Label;
            Colors colors = Common.Colors;
            labelWrapper.setTextColor(Colors.RGB(234, 83, 9));
            mostCurrent._lstsales.Clear();
            mostCurrent._pnlsetting.setVisible(false);
            mostCurrent._pnlsales.setVisible(true);
            mostCurrent._pnllog.setVisible(false);
            mostCurrent._pnlfilling.setVisible(true);
            mostCurrent._pnlsales.BringToFront();
            mostCurrent._pnlfilling.BringToFront();
            if (!_astreams.IsInitialized()) {
                return "";
            }
            _astreams.Write(("<LG>" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
            _saleevents = true;
        } else {
            mostCurrent._pnlsetting.setVisible(false);
            mostCurrent._pnlsales.setVisible(false);
            mostCurrent._pnllog.setVisible(true);
            mostCurrent._pnlfilling.setVisible(true);
            new InputDialog();
            mostCurrent._pnllog.BringToFront();
            mostCurrent._pnlfilling.BringToFront();
            _saleevents = false;
        }
        return "";
    }

    public static String _btnsettings_click() throws Exception {
        mostCurrent._pnllog.setVisible(false);
        mostCurrent._pnlsales.setVisible(false);
        mostCurrent._pnlsetting.setVisible(true);
        mostCurrent._pnlfilling.setVisible(false);
        mostCurrent._lblrate.setText(BA.ObjectToCharSequence(""));
        mostCurrent._lbltotal.setText(BA.ObjectToCharSequence(""));
        mostCurrent._lblslowflow.setText(BA.ObjectToCharSequence(""));
        mostCurrent._lblslowfast.setText(BA.ObjectToCharSequence(""));
        mostCurrent._lblhide.setText(BA.ObjectToCharSequence(""));
        mostCurrent._lblkeyboarddisplay.setText(BA.ObjectToCharSequence(""));
        mostCurrent._lblassembly.setText(BA.ObjectToCharSequence(""));
        mostCurrent._lblcorrection.setText(BA.ObjectToCharSequence(""));
        mostCurrent._lbldate.setText(BA.ObjectToCharSequence(""));
        mostCurrent._lbltime.setText(BA.ObjectToCharSequence(""));
        _astreams.Write(("<QR>" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        mostCurrent._btnsettings.setEnabled(false);
        mostCurrent._btnsales.setEnabled(false);
        mostCurrent._btnlog.setEnabled(false);
        mostCurrent._pnlsetting.BringToFront();
        return "";
    }

    public static String _btnslowfast_click() throws Exception {
        InputDialog inputDialog = new InputDialog();
        InputDialog.NumberDialog numberDialog = new InputDialog.NumberDialog();
        try {
            inputDialog.setHint("Enter Password");
            inputDialog.setInputType(2);
            inputDialog.setPasswordMode(true);
            BA ba = mostCurrent.activityBA;
            Bitmap bitmap = (Bitmap) Common.Null;
            inputDialog.Show("Enter Code For SlowFast Setting", "Enter Password", "OK", "", "", ba, bitmap);
            if (((long) Double.parseDouble(inputDialog.getInput())) == _slowhidepassword) {
                numberDialog.setShowSign(false);
                numberDialog.setDecimal(0);
                numberDialog.setDigits(1);
                numberDialog.setNumber((int) Double.parseDouble(mostCurrent._lblslowfast.getText()));
                BA ba2 = mostCurrent.activityBA;
                Bitmap bitmap2 = (Bitmap) Common.Null;
                numberDialog.Show("New Value", "OK", "Cancel", "", ba2, bitmap2);
                long number = numberDialog.getNumber();
                if (numberDialog.getResponse() == -1) {
                    _astreams.Write(("<VH" + _convertstring((int) number) + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
                    Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
                    StringBuilder sb = new StringBuilder();
                    sb.append("<QR>");
                    sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
                    _astreams.Write(sb.toString().getBytes("UTF8"));
                }
            } else {
                Common.Msgbox(BA.ObjectToCharSequence("Wrong Password"), BA.ObjectToCharSequence("Error"), mostCurrent.activityBA);
            }
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _btnslowflow_click() throws Exception {
        InputDialog inputDialog = new InputDialog();
        InputDialog.NumberDialog numberDialog = new InputDialog.NumberDialog();
        try {
            inputDialog.setHint("Enter Password");
            inputDialog.setInputType(2);
            inputDialog.setPasswordMode(true);
            BA ba = mostCurrent.activityBA;
            Bitmap bitmap = (Bitmap) Common.Null;
            inputDialog.Show("Enter Code For SlowFlow Setting", "Enter Password", "OK", "", "", ba, bitmap);
            if (((long) Double.parseDouble(inputDialog.getInput())) == _slowhidepassword) {
                numberDialog.setShowSign(false);
                numberDialog.setDecimal(0);
                numberDialog.setDigits(2);
                numberDialog.setNumber((int) Double.parseDouble(mostCurrent._lblslowflow.getText()));
                BA ba2 = mostCurrent.activityBA;
                Bitmap bitmap2 = (Bitmap) Common.Null;
                numberDialog.Show("New Value", "OK", "Cancel", "", ba2, bitmap2);
                long number = numberDialog.getNumber();
                if (numberDialog.getResponse() == -1) {
                    _astreams.Write(("<SF" + _convertstring((int) number) + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
                    Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
                    StringBuilder sb = new StringBuilder();
                    sb.append("<QR>");
                    sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
                    _astreams.Write(sb.toString().getBytes("UTF8"));
                }
            } else {
                Common.Msgbox(BA.ObjectToCharSequence("Wrong Password"), BA.ObjectToCharSequence("Error"), mostCurrent.activityBA);
            }
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _btntime_click() throws Exception {
        InputDialog inputDialog = new InputDialog();
        InputDialog.TimeDialog timeDialog = new InputDialog.TimeDialog();
        try {
            inputDialog.setHint("Enter Password");
            inputDialog.setInputType(2);
            inputDialog.setPasswordMode(true);
            BA ba = mostCurrent.activityBA;
            Bitmap bitmap = (Bitmap) Common.Null;
            inputDialog.Show("Enter Code For Time Setting", "Enter Password", "OK", "", "", ba, bitmap);
            if (((long) Double.parseDouble(inputDialog.getInput())) == _timepassword) {
                timeDialog.setHour((int) Double.parseDouble(_strhrs));
                timeDialog.setMinute((int) Double.parseDouble(_strmin));
                timeDialog.setIs24Hours(true);
                BA ba2 = mostCurrent.activityBA;
                Bitmap bitmap2 = (Bitmap) Common.Null;
                timeDialog.Show("Set Time", "Time", "OK", "Cancel", "", ba2, bitmap2);
                if (timeDialog.getResponse() != -1) {
                    return "";
                }
                if (timeDialog.getHour() < 10) {
                    _strhrs = "0" + BA.NumberToString(timeDialog.getHour());
                } else {
                    _strhrs = BA.NumberToString(timeDialog.getHour());
                }
                if (timeDialog.getMinute() < 10) {
                    _strmin = "0" + BA.NumberToString(timeDialog.getMinute());
                } else {
                    _strmin = BA.NumberToString(timeDialog.getMinute());
                }
                _astreams.Write(("<TS" + _convertstring((int) Double.parseDouble(_strhrs + _strmin + "00")) + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
                Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
                StringBuilder sb = new StringBuilder();
                sb.append("<QR>");
                sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
                _astreams.Write(sb.toString().getBytes("UTF8"));
                return "";
            }
            Common.Msgbox(BA.ObjectToCharSequence("Wrong Password"), BA.ObjectToCharSequence("Error"), mostCurrent.activityBA);
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _btntotal_click() throws Exception {
        InputDialog inputDialog = new InputDialog();
        InputDialog inputDialog2 = new InputDialog();
        try {
            inputDialog.setHint("Total Meter Password");
            inputDialog.setInputType(2);
            inputDialog.setPasswordMode(true);
            BA ba = mostCurrent.activityBA;
            Bitmap bitmap = (Bitmap) Common.Null;
            inputDialog.Show("Enter Code For Total Meter Setting", "Enter Password", "OK", "", "", ba, bitmap);
            if (((long) Double.parseDouble(inputDialog.getInput())) == _totalpassword) {
                inputDialog2.setHint("Enter New Totoal Meter Value");
                inputDialog2.setInputType(2);
                BA ba2 = mostCurrent.activityBA;
                Bitmap bitmap2 = (Bitmap) Common.Null;
                inputDialog2.Show("New Value", "Total Meter", "Ok", "Cancel", "", ba2, bitmap2);
                long j = ((long) Double.parseDouble(inputDialog2.getInput())) * 100;
                if (inputDialog2.getResponse() == -1) {
                    _astreams.Write(("<TM" + _convertstring((int) j) + ">" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
                    Common.Msgbox(BA.ObjectToCharSequence("Value Updated"), BA.ObjectToCharSequence("Info"), mostCurrent.activityBA);
                    StringBuilder sb = new StringBuilder();
                    sb.append("<QR>");
                    sb.append(BA.ObjectToString(Character.valueOf(Common.Chr(10))));
                    _astreams.Write(sb.toString().getBytes("UTF8"));
                }
            } else {
                Common.Msgbox(BA.ObjectToCharSequence("Wrong Password"), BA.ObjectToCharSequence("Error"), mostCurrent.activityBA);
            }
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _btnupdatesettings_click() throws Exception {
        _astreams.Write(("<PQ>" + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8"));
        return "";
    }

    public static String _button1_click() throws Exception {
        mostCurrent._edittext1.setText(BA.ObjectToCharSequence(mostCurrent._edittext1.getText() + "this is the line" + Common.CRLF));
        return "";
    }

    public static String _convertstring(int i) throws Exception {
        String str = i == 0 ? "00000000" : "";
        if (i > 0 && i < 10) {
            str = "0000000" + BA.NumberToString(i);
        }
        if (i > 9 && i < 100) {
            str = "000000" + BA.NumberToString(i);
        }
        if (i > 99 && i < 1000) {
            str = "00000" + BA.NumberToString(i);
        }
        if (i > 999 && i < 10000) {
            str = "0000" + BA.NumberToString(i);
        }
        if (i > 9999 && i < 100000) {
            str = "000" + BA.NumberToString(i);
        }
        if (i > 99999 && i < 1000000) {
            str = "00" + BA.NumberToString(i);
        }
        if (i <= 999999 || i >= 10000000) {
            return str;
        }
        return "0" + BA.NumberToString(i);
    }

    public static String _decode_29() throws Exception {
        try {
            main mainVar = mostCurrent;
            if (!mainVar._sf._vvvv5(mainVar._lblrx.getText(), 1, 1).equals("4")) {
                return "";
            }
            mostCurrent._btnsettings.setEnabled(false);
            mostCurrent._btnsales.setEnabled(false);
            mostCurrent._pnlsetting.setVisible(false);
            mostCurrent._pnlfilling.setVisible(true);
            mostCurrent._pnlfilling.BringToFront();
            mostCurrent._pnllog.setVisible(true);
            mostCurrent._pnllog.BringToFront();
            mostCurrent._btnrate.setEnabled(false);
            mostCurrent._btntotal.setEnabled(false);
            mostCurrent._btnslowflow.setEnabled(false);
            mostCurrent._btnslowfast.setEnabled(false);
            mostCurrent._btnhide.setEnabled(false);
            mostCurrent._btnslowfast.setEnabled(false);
            mostCurrent._btnkeyboarddisplay.setEnabled(false);
            mostCurrent._btnassembly.setEnabled(false);
            mostCurrent._btncorrection.setEnabled(false);
            mostCurrent._btndate.setEnabled(false);
            mostCurrent._btntime.setEnabled(false);
            mostCurrent._btnprinter.setEnabled(false);
            mostCurrent._btnlog.setEnabled(true);
            main mainVar2 = mostCurrent;
            mostCurrent._lbltotalmeter.setText(BA.ObjectToCharSequence(Double.valueOf(Double.parseDouble(mainVar2._sf._vvvv5(mainVar2._lblrx.getText(), 5, 8)) / 100.0d)));
            main mainVar3 = mostCurrent;
            _strtotal = BA.NumberToString(Double.parseDouble(mainVar3._sf._vvvv5(mainVar3._lblrx.getText(), 5, 8)) / 100.0d);
            main mainVar4 = mostCurrent;
            _strrate = BA.NumberToString(Double.parseDouble(mainVar4._sf._vvvv5(mainVar4._lblrx.getText(), 24, 5)) / 100.0d);
            main mainVar5 = mostCurrent;
            _stryear = mainVar5._sf._vvvv5(mainVar5._lblrx.getText(), 18, 2);
            main mainVar6 = mostCurrent;
            _strmonth = mainVar6._sf._vvvv5(mainVar6._lblrx.getText(), 20, 2);
            main mainVar7 = mostCurrent;
            _strday = mainVar7._sf._vvvv5(mainVar7._lblrx.getText(), 22, 2);
            main mainVar8 = mostCurrent;
            _strhrs = mainVar8._sf._vvvv5(mainVar8._lblrx.getText(), 24, 2);
            main mainVar9 = mostCurrent;
            _strmin = mainVar9._sf._vvvv5(mainVar9._lblrx.getText(), 26, 2);
            main mainVar10 = mostCurrent;
            _strsec = mainVar10._sf._vvvv5(mainVar10._lblrx.getText(), 28, 2);
            _strdate = _strday + "/" + _strmonth + "/" + _stryear;
            _strtime = _strhrs + ":" + _strmin + ":" + _strsec;
            mostCurrent._txtlog.setText(BA.ObjectToCharSequence(mostCurrent._txtlog.getText() + BA.ObjectToString(Character.valueOf(Common.Chr(10))) + "> Started: Rt " + _strrate + " Tm " + _strtotal + " at " + _strtime + " Hrs " + _strdate));
            EditTextWrapper editTextWrapper = mostCurrent._txtlog;
            editTextWrapper.setSelectionStart(editTextWrapper.getText().length());
            byte[] bytes = (("> Sale Started: Rt " + _strrate + " Tm " + _strtotal + " at " + _strtime + " Hrs " + _strdate) + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8");
            new File.OutputStreamWrapper();
            File file = Common.File;
            File file2 = Common.File;
            File.OutputStreamWrapper outputStreamWrapperOpenOutput = File.OpenOutput(File.getDirRootExternal(), "AlphaLog.txt", true);
            outputStreamWrapperOpenOutput.WriteBytes(bytes, 0, bytes.length);
            outputStreamWrapperOpenOutput.Close();
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _decode_3() throws Exception {
        try {
            main mainVar = mostCurrent;
            if (!mainVar._sf._vvvv5(mainVar._lblrx.getText(), 1, 1).equals("P")) {
                return "";
            }
            main mainVar2 = mostCurrent;
            if (mainVar2._sf._vvvv5(mainVar2._lblrx.getText(), 2, 1).equals("0")) {
                mostCurrent._label10.setText(BA.ObjectToCharSequence("9600 Baud "));
            } else {
                mostCurrent._label10.setText(BA.ObjectToCharSequence("115200 Baud "));
            }
            main mainVar3 = mostCurrent;
            if (mainVar3._sf._vvvv5(mainVar3._lblrx.getText(), 3, 1).equals("0")) {
                _printercolumn = false;
                mostCurrent._label10.setText(BA.ObjectToCharSequence(mostCurrent._label10.getText() + "32 Column "));
                return "";
            }
            _printercolumn = true;
            mostCurrent._label10.setText(BA.ObjectToCharSequence(mostCurrent._label10.getText() + "40 Column"));
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _decode_33() throws Exception {
        try {
            main mainVar = mostCurrent;
            String str_vvvv5 = mainVar._sf._vvvv5(mainVar._lblrx.getText(), 4, 1);
            if (str_vvvv5.equals("0")) {
                mostCurrent._lblproduct.setText(BA.ObjectToCharSequence("Petrol"));
            }
            if (str_vvvv5.equals("1")) {
                mostCurrent._lblproduct.setText(BA.ObjectToCharSequence("Diesel"));
            }
            if (str_vvvv5.equals("2")) {
                mostCurrent._lblproduct.setText(BA.ObjectToCharSequence("HOBC"));
            }
            if (str_vvvv5.equals("3")) {
                mostCurrent._lblproduct.setText(BA.ObjectToCharSequence("Kerosene"));
            }
            main mainVar2 = mostCurrent;
            mainVar2._lblunitid.setText(BA.ObjectToCharSequence(mainVar2._sf._vvvv5(mainVar2._lblrx.getText(), 2, 2)));
            main mainVar3 = mostCurrent;
            String str_vvvv52 = mainVar3._sf._vvvv5(mainVar3._lblrx.getText(), 1, 1);
            if (str_vvvv52.equals("5")) {
                if (!mostCurrent._imgnzl.getVisible()) {
                    mostCurrent._imgnzl.setVisible(true);
                }
            } else if (mostCurrent._imgnzl.getVisible()) {
                mostCurrent._imgnzl.setVisible(false);
                mostCurrent._btnsettings.setEnabled(true);
                mostCurrent._btnsales.setEnabled(true);
            }
            if (str_vvvv52.equals("0") || str_vvvv52.equals("5")) {
                mostCurrent._lblpreset.setText(BA.ObjectToCharSequence(""));
                if (!mostCurrent._lbldisplayliter.getVisible()) {
                    mostCurrent._lbldisplayliter.setVisible(true);
                }
                main mainVar4 = mostCurrent;
                mostCurrent._lbldisplayprice.setText(BA.ObjectToCharSequence(Common.NumberFormat2(Double.parseDouble(mainVar4._sf._vvvv5(mainVar4._lblrx.getText(), 5, 8)) / 100.0d, 0, 2, 2, false)));
                main mainVar5 = mostCurrent;
                mostCurrent._lbldisplayliter.setText(BA.ObjectToCharSequence(Common.NumberFormat2(Double.parseDouble(mainVar5._sf._vvvv5(mainVar5._lblrx.getText(), 13, 8)) / 100.0d, 0, 2, 2, false)));
                main mainVar6 = mostCurrent;
                mostCurrent._lbldisplayrate.setText(BA.ObjectToCharSequence(Common.NumberFormat2(Double.parseDouble(mainVar6._sf._vvvv5(mainVar6._lblrx.getText(), 21, 5)) / 100.0d, 0, 2, 2, false)));
                main mainVar7 = mostCurrent;
                mostCurrent._lbltotalmeter.setText(BA.ObjectToCharSequence(Double.valueOf(Double.parseDouble(mainVar7._sf._vvvv5(mainVar7._lblrx.getText(), 26, 8)) / 100.0d)));
            }
            if (str_vvvv52.equals("P")) {
                mostCurrent._lblpreset.setText(BA.ObjectToCharSequence("Reupees Preset"));
                mostCurrent._lbldisplayliter.setVisible(false);
                main mainVar8 = mostCurrent;
                mostCurrent._lbldisplayprice.setText(BA.ObjectToCharSequence(Common.NumberFormat2(Double.parseDouble(mainVar8._sf._vvvv5(mainVar8._lblrx.getText(), 5, 8)), 0, 2, 2, false)));
                main mainVar9 = mostCurrent;
                mostCurrent._lbldisplayrate.setText(BA.ObjectToCharSequence(Common.NumberFormat2(Double.parseDouble(mainVar9._sf._vvvv5(mainVar9._lblrx.getText(), 21, 5)) / 100.0d, 0, 2, 2, false)));
                main mainVar10 = mostCurrent;
                mostCurrent._lbltotalmeter.setText(BA.ObjectToCharSequence(Double.valueOf(Double.parseDouble(mainVar10._sf._vvvv5(mainVar10._lblrx.getText(), 26, 8)) / 100.0d)));
            }
            if (str_vvvv52.equals("L")) {
                mostCurrent._lblpreset.setText(BA.ObjectToCharSequence("Liters Preset"));
                mostCurrent._lbldisplayliter.setVisible(false);
                main mainVar11 = mostCurrent;
                mostCurrent._lbldisplayprice.setText(BA.ObjectToCharSequence(Common.NumberFormat2(Double.parseDouble(mainVar11._sf._vvvv5(mainVar11._lblrx.getText(), 5, 8)), 0, 2, 2, false)));
                main mainVar12 = mostCurrent;
                mostCurrent._lbldisplayrate.setText(BA.ObjectToCharSequence(Common.NumberFormat2(Double.parseDouble(mainVar12._sf._vvvv5(mainVar12._lblrx.getText(), 21, 5)) / 100.0d, 0, 2, 2, false)));
                main mainVar13 = mostCurrent;
                mostCurrent._lbltotalmeter.setText(BA.ObjectToCharSequence(Double.valueOf(Double.parseDouble(mainVar13._sf._vvvv5(mainVar13._lblrx.getText(), 26, 8)) / 100.0d)));
            }
        } catch (Exception e) {
            processBA.setLastException(e);
        }
        return "";
    }

    public static String _decode_36() throws Exception {
        try {
            main mainVar = mostCurrent;
            if (!mainVar._sf._vvvv5(mainVar._lblrx.getText(), 1, 1).equals("2")) {
                return "";
            }
            main mainVar2 = mostCurrent;
            int i = (int) Double.parseDouble(mainVar2._sf._vvvv5(mainVar2._lblrx.getText(), 2, 2));
            main mainVar3 = mostCurrent;
            double d = Double.parseDouble(mainVar3._sf._vvvv5(mainVar3._lblrx.getText(), 4, 8)) / 100.0d;
            main mainVar4 = mostCurrent;
            double d2 = Double.parseDouble(mainVar4._sf._vvvv5(mainVar4._lblrx.getText(), 12, 8)) / 100.0d;
            main mainVar5 = mostCurrent;
            double d3 = Double.parseDouble(mainVar5._sf._vvvv5(mainVar5._lblrx.getText(), 20, 5)) / 100.0d;
            ListViewWrapper listViewWrapper = mostCurrent._lstsales;
            StringBuilder sb = new StringBuilder();
            sb.append(BA.NumberToString(i));
            sb.append("# ");
            sb.append(BA.NumberToString(d));
            sb.append(" Rs. ");
            sb.append(BA.NumberToString(d2));
            sb.append(" Ltr. ");
            sb.append(BA.NumberToString(d3));
            sb.append(" Rs/Ltr at ");
            main mainVar6 = mostCurrent;
            sb.append(mainVar6._sf._vvvv5(mainVar6._lblrx.getText(), 31, 2));
            sb.append(":");
            main mainVar7 = mostCurrent;
            sb.append(mainVar7._sf._vvvv5(mainVar7._lblrx.getText(), 33, 2));
            sb.append(":");
            main mainVar8 = mostCurrent;
            sb.append(mainVar8._sf._vvvv5(mainVar8._lblrx.getText(), 35, 2));
            sb.append(" ");
            main mainVar9 = mostCurrent;
            sb.append(mainVar9._sf._vvvv5(mainVar9._lblrx.getText(), 29, 2));
            sb.append("/");
            main mainVar10 = mostCurrent;
            sb.append(mainVar10._sf._vvvv5(mainVar10._lblrx.getText(), 27, 2));
            sb.append("/");
            main mainVar11 = mostCurrent;
            sb.append(mainVar11._sf._vvvv5(mainVar11._lblrx.getText(), 25, 2));
            listViewWrapper.AddSingleLine(BA.ObjectToCharSequence(sb.toString()));
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _decode_37() throws Exception {
        try {
            main mainVar = mostCurrent;
            String str_vvvv5 = mainVar._sf._vvvv5(mainVar._lblrx.getText(), 1, 1);
            if (str_vvvv5.equals("6")) {
                mostCurrent._btnsettings.setEnabled(true);
                mostCurrent._btnsales.setEnabled(true);
                main mainVar2 = mostCurrent;
                mostCurrent._lbldisplayprice.setText(BA.ObjectToCharSequence(Common.NumberFormat2(Double.parseDouble(mainVar2._sf._vvvv5(mainVar2._lblrx.getText(), 5, 8)) / 100.0d, 0, 2, 2, false)));
                main mainVar3 = mostCurrent;
                mostCurrent._lbldisplayliter.setText(BA.ObjectToCharSequence(Common.NumberFormat2(Double.parseDouble(mainVar3._sf._vvvv5(mainVar3._lblrx.getText(), 13, 8)) / 100.0d, 0, 2, 2, false)));
                main mainVar4 = mostCurrent;
                mostCurrent._lbldisplayrate.setText(BA.ObjectToCharSequence(Common.NumberFormat2(Double.parseDouble(mainVar4._sf._vvvv5(mainVar4._lblrx.getText(), 21, 5)) / 100.0d, 0, 2, 2, false)));
                main mainVar5 = mostCurrent;
                _stryear = mainVar5._sf._vvvv5(mainVar5._lblrx.getText(), 26, 2);
                main mainVar6 = mostCurrent;
                _strmonth = mainVar6._sf._vvvv5(mainVar6._lblrx.getText(), 28, 2);
                main mainVar7 = mostCurrent;
                _strday = mainVar7._sf._vvvv5(mainVar7._lblrx.getText(), 30, 2);
                main mainVar8 = mostCurrent;
                _strhrs = mainVar8._sf._vvvv5(mainVar8._lblrx.getText(), 32, 2);
                main mainVar9 = mostCurrent;
                _strmin = mainVar9._sf._vvvv5(mainVar9._lblrx.getText(), 34, 2);
                main mainVar10 = mostCurrent;
                _strsec = mainVar10._sf._vvvv5(mainVar10._lblrx.getText(), 36, 2);
                _strdate = _strday + "/" + _strmonth + "/" + _stryear;
                _strtime = _strhrs + ":" + _strmin + ":" + _strsec;
                mostCurrent._txtlog.setText(BA.ObjectToCharSequence(mostCurrent._txtlog.getText() + BA.ObjectToString(Character.valueOf(Common.Chr(10))) + "> Stopped With Out Sale: at " + _strtime + " Hrs " + _strdate));
                EditTextWrapper editTextWrapper = mostCurrent._txtlog;
                editTextWrapper.setSelectionStart(editTextWrapper.getText().length());
                byte[] bytes = (("> Stopped With Out Sale: at " + _strtime + " Hrs " + _strdate) + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8");
                new File.OutputStreamWrapper();
                File file = Common.File;
                File file2 = Common.File;
                File.OutputStreamWrapper outputStreamWrapperOpenOutput = File.OpenOutput(File.getDirRootExternal(), "AlphaLog.txt", true);
                outputStreamWrapperOpenOutput.WriteBytes(bytes, 0, bytes.length);
                outputStreamWrapperOpenOutput.Close();
            }
            if (!str_vvvv5.equals("7")) {
                return "";
            }
            mostCurrent._btnsettings.setEnabled(true);
            mostCurrent._btnsales.setEnabled(true);
            main mainVar11 = mostCurrent;
            double d = Double.parseDouble(mainVar11._sf._vvvv5(mainVar11._lblrx.getText(), 5, 8)) / 100.0d;
            mostCurrent._lbldisplayprice.setText(BA.ObjectToCharSequence(Common.NumberFormat2(d, 0, 2, 2, false)));
            _strprice = BA.NumberToString(d);
            main mainVar12 = mostCurrent;
            double d2 = Double.parseDouble(mainVar12._sf._vvvv5(mainVar12._lblrx.getText(), 13, 8)) / 100.0d;
            mostCurrent._lbldisplayliter.setText(BA.ObjectToCharSequence(Common.NumberFormat2(d2, 0, 2, 2, false)));
            _strliter = BA.NumberToString(d2);
            main mainVar13 = mostCurrent;
            double d3 = Double.parseDouble(mainVar13._sf._vvvv5(mainVar13._lblrx.getText(), 21, 5)) / 100.0d;
            mostCurrent._lbldisplayrate.setText(BA.ObjectToCharSequence(Common.NumberFormat2(d3, 0, 2, 2, false)));
            _strrate = BA.NumberToString(d3);
            main mainVar14 = mostCurrent;
            _stryear = mainVar14._sf._vvvv5(mainVar14._lblrx.getText(), 26, 2);
            main mainVar15 = mostCurrent;
            _strmonth = mainVar15._sf._vvvv5(mainVar15._lblrx.getText(), 28, 2);
            main mainVar16 = mostCurrent;
            _strday = mainVar16._sf._vvvv5(mainVar16._lblrx.getText(), 30, 2);
            main mainVar17 = mostCurrent;
            _strhrs = mainVar17._sf._vvvv5(mainVar17._lblrx.getText(), 32, 2);
            main mainVar18 = mostCurrent;
            _strmin = mainVar18._sf._vvvv5(mainVar18._lblrx.getText(), 34, 2);
            main mainVar19 = mostCurrent;
            _strsec = mainVar19._sf._vvvv5(mainVar19._lblrx.getText(), 36, 2);
            _strdate = _strday + "/" + _strmonth + "/" + _stryear;
            _strtime = _strhrs + ":" + _strmin + ":" + _strsec;
            mostCurrent._txtlog.setText(BA.ObjectToCharSequence(mostCurrent._txtlog.getText() + BA.ObjectToString(Character.valueOf(Common.Chr(10))) + "> Closed: Rs " + _strprice + " Ltr " + _strliter + " Rt " + _strrate + " at " + _strtime + " Hrs " + _strdate));
            EditTextWrapper editTextWrapper2 = mostCurrent._txtlog;
            editTextWrapper2.setSelectionStart(editTextWrapper2.getText().length());
            byte[] bytes2 = (("> Sale Closed: Rs " + _strprice + " Ltr " + _strliter + " Rt " + _strrate + " at " + _strtime + " Hrs " + _strdate) + BA.ObjectToString(Character.valueOf(Common.Chr(10)))).getBytes("UTF8");
            new File.OutputStreamWrapper();
            File file3 = Common.File;
            File file4 = Common.File;
            File.OutputStreamWrapper outputStreamWrapperOpenOutput2 = File.OpenOutput(File.getDirRootExternal(), "AlphaLog.txt", true);
            outputStreamWrapperOpenOutput2.WriteBytes(bytes2, 0, bytes2.length);
            outputStreamWrapperOpenOutput2.Close();
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _decode_42() throws Exception {
        try {
            main mainVar = mostCurrent;
            if (!mainVar._sf._vvvv5(mainVar._lblrx.getText(), 1, 1).equals("1")) {
                return "";
            }
            main mainVar2 = mostCurrent;
            mainVar2._lblunitid.setText(BA.ObjectToCharSequence(mainVar2._sf._vvvv5(mainVar2._lblrx.getText(), 2, 2)));
            main mainVar3 = mostCurrent;
            mainVar3._lblproduct.setText(BA.ObjectToCharSequence(mainVar3._sf._vvvv5(mainVar3._lblrx.getText(), 4, 1)));
            main mainVar4 = mostCurrent;
            mostCurrent._lbltotalmeter.setText(BA.ObjectToCharSequence(Double.valueOf(Double.parseDouble(mainVar4._sf._vvvv5(mainVar4._lblrx.getText(), 5, 8)) / 100.0d)));
            main mainVar5 = mostCurrent;
            mainVar5._lblunitid.setText(BA.ObjectToCharSequence(mainVar5._sf._vvvv5(mainVar5._lblrx.getText(), 2, 2)));
            main mainVar6 = mostCurrent;
            mostCurrent._lbltotal.setText(BA.ObjectToCharSequence(Double.valueOf(Double.parseDouble(mainVar6._sf._vvvv5(mainVar6._lblrx.getText(), 5, 8)) / 100.0d)));
            main mainVar7 = mostCurrent;
            double d = Double.parseDouble(mainVar7._sf._vvvv5(mainVar7._lblrx.getText(), 13, 3));
            main mainVar8 = mostCurrent;
            _strcorrectionsetting = mainVar8._sf._vvvv5(mainVar8._lblrx.getText(), 13, 3);
            if (d == 100.0d) {
                mostCurrent._lblcorrection.setText(BA.ObjectToCharSequence("0"));
            }
            if (d > 100.0d) {
                mostCurrent._lblcorrection.setText(BA.ObjectToCharSequence("+ " + BA.NumberToString(d - 100.0d)));
            }
            if (d < 100.0d) {
                mostCurrent._lblcorrection.setText(BA.ObjectToCharSequence("- " + BA.NumberToString(100.0d - d)));
            }
            main mainVar9 = mostCurrent;
            double d2 = Double.parseDouble(mainVar9._sf._vvvv5(mainVar9._lblrx.getText(), 16, 3));
            main mainVar10 = mostCurrent;
            _strassemblysetting = mainVar10._sf._vvvv5(mainVar10._lblrx.getText(), 16, 3);
            if (d2 == 100.0d) {
                mostCurrent._lblassembly.setText(BA.ObjectToCharSequence("0"));
            }
            if (d2 > 100.0d) {
                mostCurrent._lblassembly.setText(BA.ObjectToCharSequence("+ " + BA.NumberToString(d2 - 100.0d)));
            }
            if (d2 < 100.0d) {
                mostCurrent._lblassembly.setText(BA.ObjectToCharSequence("- " + BA.NumberToString(100.0d - d2)));
            }
            main mainVar11 = mostCurrent;
            mainVar11._lblhide.setText(BA.ObjectToCharSequence(mainVar11._sf._vvvv5(mainVar11._lblrx.getText(), 19, 2)));
            main mainVar12 = mostCurrent;
            String str_vvvv5 = mainVar12._sf._vvvv5(mainVar12._lblrx.getText(), 21, 1);
            if (str_vvvv5.equals("0")) {
                mostCurrent._lblkeyboarddisplay.setText(BA.ObjectToCharSequence("On Main Display"));
            }
            if (str_vvvv5.equals("1")) {
                mostCurrent._lblkeyboarddisplay.setText(BA.ObjectToCharSequence("On Keyboard Display"));
            }
            if (str_vvvv5.equals("2")) {
                mostCurrent._lblkeyboarddisplay.setText(BA.ObjectToCharSequence("Keyboard + Main"));
            }
            main mainVar13 = mostCurrent;
            mainVar13._lblslowflow.setText(BA.ObjectToCharSequence(mainVar13._sf._vvvv5(mainVar13._lblrx.getText(), 22, 2)));
            main mainVar14 = mostCurrent;
            mainVar14._lblslowfast.setText(BA.ObjectToCharSequence(mainVar14._sf._vvvv5(mainVar14._lblrx.getText(), 24, 2)));
            main mainVar15 = mostCurrent;
            mostCurrent._lblrate.setText(BA.ObjectToCharSequence(Double.valueOf(Double.parseDouble(mainVar15._sf._vvvv5(mainVar15._lblrx.getText(), 26, 5)) / 100.0d)));
            main mainVar16 = mostCurrent;
            _stryear = mainVar16._sf._vvvv5(mainVar16._lblrx.getText(), 31, 2);
            main mainVar17 = mostCurrent;
            _strmonth = mainVar17._sf._vvvv5(mainVar17._lblrx.getText(), 33, 2);
            main mainVar18 = mostCurrent;
            _strday = mainVar18._sf._vvvv5(mainVar18._lblrx.getText(), 35, 2);
            main mainVar19 = mostCurrent;
            _strhrs = mainVar19._sf._vvvv5(mainVar19._lblrx.getText(), 37, 2);
            main mainVar20 = mostCurrent;
            _strmin = mainVar20._sf._vvvv5(mainVar20._lblrx.getText(), 39, 2);
            main mainVar21 = mostCurrent;
            _strsec = mainVar21._sf._vvvv5(mainVar21._lblrx.getText(), 41, 2);
            mostCurrent._lbldate.setText(BA.ObjectToCharSequence(_strday + "/" + _strmonth + "/" + _stryear));
            mostCurrent._lbltime.setText(BA.ObjectToCharSequence(_strhrs + ":" + _strmin + ":" + _strsec));
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _decode_43() throws Exception {
        try {
            main mainVar = mostCurrent;
            String str_vvvv5 = mainVar._sf._vvvv5(mainVar._lblrx.getText(), 1, 2);
            if (str_vvvv5.equals("L1")) {
                main mainVar2 = mostCurrent;
                mostCurrent._txtprinter1.setText(BA.ObjectToCharSequence(mainVar2._sf._vvvv5(mainVar2._lblrx.getText(), 4, 20)));
                main mainVar3 = mostCurrent;
                str_vvvv5 = mainVar3._sf._vvvv5(mainVar3._lblrx.getText(), 24, 20);
                mostCurrent._txtprinter2.setText(BA.ObjectToCharSequence(str_vvvv5));
            }
            if (str_vvvv5.equals("L2")) {
                main mainVar4 = mostCurrent;
                mostCurrent._txtprinter3.setText(BA.ObjectToCharSequence(mainVar4._sf._vvvv5(mainVar4._lblrx.getText(), 4, 20)));
                main mainVar5 = mostCurrent;
                str_vvvv5 = mainVar5._sf._vvvv5(mainVar5._lblrx.getText(), 24, 20);
                mostCurrent._txtprinter4.setText(BA.ObjectToCharSequence(str_vvvv5));
            }
            if (str_vvvv5.equals("L3")) {
                main mainVar6 = mostCurrent;
                mostCurrent._txtprinter5.setText(BA.ObjectToCharSequence(mainVar6._sf._vvvv5(mainVar6._lblrx.getText(), 4, 20)));
                main mainVar7 = mostCurrent;
                str_vvvv5 = mainVar7._sf._vvvv5(mainVar7._lblrx.getText(), 24, 20);
                mostCurrent._txtprinter6.setText(BA.ObjectToCharSequence(str_vvvv5));
            }
            if (!str_vvvv5.equals("L4")) {
                return "";
            }
            main mainVar8 = mostCurrent;
            mostCurrent._txtprinter7.setText(BA.ObjectToCharSequence(mainVar8._sf._vvvv5(mainVar8._lblrx.getText(), 4, 20)));
            main mainVar9 = mostCurrent;
            mostCurrent._txtprinter8.setText(BA.ObjectToCharSequence(mainVar9._sf._vvvv5(mainVar9._lblrx.getText(), 24, 20)));
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _decode_52() throws Exception {
        try {
            main mainVar = mostCurrent;
            if (!mainVar._sf._vvvv5(mainVar._lblrx.getText(), 1, 1).equals(BA.NumberToString(3))) {
                return "";
            }
            main mainVar2 = mostCurrent;
            _ratepassword = (long) Double.parseDouble(mainVar2._sf._vvvv5(mainVar2._lblrx.getText(), 5, 6));
            main mainVar3 = mostCurrent;
            _slowhidepassword = (long) Double.parseDouble(mainVar3._sf._vvvv5(mainVar3._lblrx.getText(), 11, 6));
            main mainVar4 = mostCurrent;
            _adjustpassword = (long) Double.parseDouble(mainVar4._sf._vvvv5(mainVar4._lblrx.getText(), 17, 6));
            main mainVar5 = mostCurrent;
            _totalpassword = (long) Double.parseDouble(mainVar5._sf._vvvv5(mainVar5._lblrx.getText(), 29, 6));
            main mainVar6 = mostCurrent;
            _lcdviewpassword = (long) Double.parseDouble(mainVar6._sf._vvvv5(mainVar6._lblrx.getText(), 35, 6));
            main mainVar7 = mostCurrent;
            _timepassword = (long) Double.parseDouble(mainVar7._sf._vvvv5(mainVar7._lblrx.getText(), 41, 6));
            main mainVar8 = mostCurrent;
            _datepassword = (long) Double.parseDouble(mainVar8._sf._vvvv5(mainVar8._lblrx.getText(), 47, 6));
            mostCurrent._btnrate.setEnabled(true);
            mostCurrent._btnslowflow.setEnabled(true);
            mostCurrent._btnslowfast.setEnabled(true);
            mostCurrent._btnhide.setEnabled(true);
            mostCurrent._btntotal.setEnabled(true);
            mostCurrent._btnkeyboarddisplay.setEnabled(true);
            mostCurrent._btnassembly.setEnabled(true);
            mostCurrent._btncorrection.setEnabled(true);
            mostCurrent._btndate.setEnabled(true);
            mostCurrent._btntime.setEnabled(true);
            mostCurrent._btnprinter.setEnabled(true);
            return "";
        } catch (Exception e) {
            processBA.setLastException(e);
            return "";
        }
    }

    public static String _delay(long j) throws Exception {
        DateTime dateTime = Common.DateTime;
        long now = DateTime.getNow() + j;
        DateTime dateTime2 = Common.DateTime;
        long now2 = DateTime.getNow();
        while (now2 < now) {
            DateTime dateTime3 = Common.DateTime;
            now2 = DateTime.getNow();
            if (now < now2) {
                return "";
            }
            Common.DoEvents();
        }
        return "";
    }

    public static String _globals() throws Exception {
        _saleevents = false;
        _ln = 0;
        _st = 0;
        _sp = 0;
        main mainVar = mostCurrent;
        _msg = "";
        _x = "";
        mainVar._sf = new stringfunctions();
        _printercolumn = false;
        main mainVar2 = mostCurrent;
        _strunitid = "";
        _strproductid = "";
        _strtotalmeter = "";
        _strpulsesetting = "";
        _strassemblysetting = "";
        _strcorrectionsetting = "";
        _strhidepulses = "";
        _strlcdview = "";
        _strslowflow = "";
        _strrate = "";
        _stryear = "";
        _strmonth = "";
        _strday = "";
        _strhrs = "";
        _strmin = "";
        _strsec = "";
        _strdate = "";
        _strtime = "";
        _strtotal = "";
        _strprice = "";
        _strliter = "";
        _ratepassword = 0L;
        _slowhidepassword = 0L;
        _adjustpassword = 0L;
        _idpassword = 0L;
        _totalpassword = 0L;
        _lcdviewpassword = 0L;
        _timepassword = 0L;
        _datepassword = 0L;
        mainVar2._edittext2 = new EditTextWrapper();
        mostCurrent._lblrx = new LabelWrapper();
        mostCurrent._lblrx2 = new LabelWrapper();
        mostCurrent._pidle = new PanelWrapper();
        mostCurrent._lblunitid = new LabelWrapper();
        mostCurrent._lblproduct = new LabelWrapper();
        mostCurrent._lbldisplayliter = new LabelWrapper();
        mostCurrent._lbldisplayprice = new LabelWrapper();
        mostCurrent._lbldisplayrate = new LabelWrapper();
        mostCurrent._imgnzl = new ImageViewWrapper();
        mostCurrent._lblpreset = new LabelWrapper();
        mostCurrent._lbltotalmeter = new LabelWrapper();
        mostCurrent._btnsales = new ButtonWrapper();
        mostCurrent._lstsales = new ListViewWrapper();
        mostCurrent._pnlsales = new PanelWrapper();
        mostCurrent._pnlsetting = new PanelWrapper();
        mostCurrent._btnlog = new ButtonWrapper();
        mostCurrent._pnllog = new PanelWrapper();
        mostCurrent._btnsettings = new ButtonWrapper();
        mostCurrent._edittext1 = new EditTextWrapper();
        mostCurrent._lblrate = new LabelWrapper();
        mostCurrent._lbltotal = new LabelWrapper();
        mostCurrent._lblslowflow = new LabelWrapper();
        mostCurrent._lblhide = new LabelWrapper();
        mostCurrent._lblkeyboarddisplay = new LabelWrapper();
        mostCurrent._lblassembly = new LabelWrapper();
        mostCurrent._lblcorrection = new LabelWrapper();
        mostCurrent._lbldate = new LabelWrapper();
        mostCurrent._lbltime = new LabelWrapper();
        mostCurrent._btnupdatesettings = new ButtonWrapper();
        mostCurrent._btnrate = new ButtonWrapper();
        mostCurrent._btntotal = new ButtonWrapper();
        mostCurrent._btnslowflow = new ButtonWrapper();
        mostCurrent._btnhide = new ButtonWrapper();
        mostCurrent._btnkeyboarddisplay = new ButtonWrapper();
        mostCurrent._btnassembly = new ButtonWrapper();
        mostCurrent._btncorrection = new ButtonWrapper();
        mostCurrent._btndate = new ButtonWrapper();
        mostCurrent._btntime = new ButtonWrapper();
        mostCurrent._btnprinter = new ButtonWrapper();
        mostCurrent._lblsystemparameter = new LabelWrapper();
        mostCurrent._pnlfilling = new PanelWrapper();
        mostCurrent._btnback = new ButtonWrapper();
        mostCurrent._txtlog = new EditTextWrapper();
        mostCurrent._btnprinter1 = new ButtonWrapper();
        mostCurrent._btnprinter2 = new ButtonWrapper();
        mostCurrent._btnprinter3 = new ButtonWrapper();
        mostCurrent._btnprinter4 = new ButtonWrapper();
        mostCurrent._btnprinter5 = new ButtonWrapper();
        mostCurrent._btnprinter6 = new ButtonWrapper();
        mostCurrent._btnprinter7 = new ButtonWrapper();
        mostCurrent._btnprinter8 = new ButtonWrapper();
        mostCurrent._txtprinter1 = new EditTextWrapper();
        mostCurrent._txtprinter2 = new EditTextWrapper();
        mostCurrent._txtprinter3 = new EditTextWrapper();
        mostCurrent._txtprinter4 = new EditTextWrapper();
        mostCurrent._txtprinter5 = new EditTextWrapper();
        mostCurrent._txtprinter6 = new EditTextWrapper();
        mostCurrent._txtprinter7 = new EditTextWrapper();
        mostCurrent._txtprinter8 = new EditTextWrapper();
        mostCurrent._lblprintlen1 = new LabelWrapper();
        mostCurrent._lblprintlen2 = new LabelWrapper();
        mostCurrent._lblprintlen3 = new LabelWrapper();
        mostCurrent._lblprintlen4 = new LabelWrapper();
        mostCurrent._lblprintlen5 = new LabelWrapper();
        mostCurrent._lblprintlen6 = new LabelWrapper();
        mostCurrent._lblprintlen7 = new LabelWrapper();
        mostCurrent._lblprintlen8 = new LabelWrapper();
        mostCurrent._btn9600 = new ButtonWrapper();
        mostCurrent._btn115200 = new ButtonWrapper();
        mostCurrent._btn32col = new ButtonWrapper();
        mostCurrent._btn40col = new ButtonWrapper();
        mostCurrent._label10 = new LabelWrapper();
        mostCurrent._pnlprinter = new PanelWrapper();
        mostCurrent._btnprinterback = new ButtonWrapper();
        mostCurrent._pnllogo = new PanelWrapper();
        mostCurrent._pnlbackground = new PanelWrapper();
        mostCurrent._lblslowfast = new LabelWrapper();
        mostCurrent._btnslowfast = new ButtonWrapper();
        mostCurrent._label9 = new LabelWrapper();
        return "";
    }

    public static void initializeProcessGlobals() {
        if (processGlobalsRun) {
            return;
        }
        processGlobalsRun = true;
        try {
            _process_globals();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    public static String _process_globals() throws Exception {
        _astreams = new AsyncStreams();
        _socket1 = new SocketWrapper();
        _ws = new Phone.PhoneWakeState();
        return "";
    }

    public static String _socket1_connected(boolean z) throws Exception {
        if (!z) {
            Common.Msgbox(BA.ObjectToCharSequence("No FDX system found. Please check your WiFi Settings. Visit www.muxtronics.com for more information"), BA.ObjectToCharSequence("Connection Error"), mostCurrent.activityBA);
            Common.ExitApplication();
            return "";
        }
        _astreams.Initialize(processBA, _socket1.getInputStream(), _socket1.getOutputStream(), "AStreams");
        return "";
    }

    public static String _txtlog_focuschanged(boolean z) throws Exception {
        mostCurrent._pnlfilling.RequestFocus();
        return "";
    }

    public static String _txtlog_textchanged(String str, String str2) throws Exception {
        if (str2.length() > 5000) {
            mostCurrent._txtlog.setText(BA.ObjectToCharSequence(""));
        }
        return "";
    }

    public static String _txtprinter1_textchanged(String str, String str2) throws Exception {
        int i = !_printercolumn ? 16 : 20;
        String text = mostCurrent._txtprinter1.getText();
        if (text.length() > i) {
            main mainVar = mostCurrent;
            text = mainVar._sf._vvvv5(mainVar._txtprinter1.getText(), 1, i);
            mostCurrent._txtprinter1.setText(BA.ObjectToCharSequence(text));
            mostCurrent._txtprinter1.setSelectionStart(i);
        }
        mostCurrent._lblprintlen1.setText(BA.ObjectToCharSequence(Integer.valueOf(text.length())));
        return "";
    }

    public static String _txtprinter2_textchanged(String str, String str2) throws Exception {
        int i = !_printercolumn ? 16 : 20;
        String text = mostCurrent._txtprinter2.getText();
        if (text.length() > i) {
            main mainVar = mostCurrent;
            text = mainVar._sf._vvvv5(mainVar._txtprinter2.getText(), 1, i);
            mostCurrent._txtprinter2.setText(BA.ObjectToCharSequence(text));
            mostCurrent._txtprinter2.setSelectionStart(i);
        }
        mostCurrent._lblprintlen2.setText(BA.ObjectToCharSequence(Integer.valueOf(text.length())));
        return "";
    }

    public static String _txtprinter3_textchanged(String str, String str2) throws Exception {
        int i = !_printercolumn ? 16 : 20;
        String text = mostCurrent._txtprinter3.getText();
        if (text.length() > i) {
            main mainVar = mostCurrent;
            text = mainVar._sf._vvvv5(mainVar._txtprinter3.getText(), 1, i);
            mostCurrent._txtprinter3.setText(BA.ObjectToCharSequence(text));
            mostCurrent._txtprinter3.setSelectionStart(i);
        }
        mostCurrent._lblprintlen3.setText(BA.ObjectToCharSequence(Integer.valueOf(text.length())));
        return "";
    }

    public static String _txtprinter4_textchanged(String str, String str2) throws Exception {
        int i = !_printercolumn ? 16 : 20;
        String text = mostCurrent._txtprinter4.getText();
        if (text.length() > i) {
            main mainVar = mostCurrent;
            text = mainVar._sf._vvvv5(mainVar._txtprinter4.getText(), 1, i);
            mostCurrent._txtprinter4.setText(BA.ObjectToCharSequence(text));
            mostCurrent._txtprinter4.setSelectionStart(i);
        }
        mostCurrent._lblprintlen4.setText(BA.ObjectToCharSequence(Integer.valueOf(text.length())));
        return "";
    }

    public static String _txtprinter5_textchanged(String str, String str2) throws Exception {
        int i = !_printercolumn ? 16 : 20;
        String text = mostCurrent._txtprinter5.getText();
        if (text.length() > i) {
            main mainVar = mostCurrent;
            text = mainVar._sf._vvvv5(mainVar._txtprinter5.getText(), 1, i);
            mostCurrent._txtprinter5.setText(BA.ObjectToCharSequence(text));
            mostCurrent._txtprinter5.setSelectionStart(i);
        }
        mostCurrent._lblprintlen5.setText(BA.ObjectToCharSequence(Integer.valueOf(text.length())));
        return "";
    }

    public static String _txtprinter6_textchanged(String str, String str2) throws Exception {
        int i = !_printercolumn ? 16 : 20;
        String text = mostCurrent._txtprinter6.getText();
        if (text.length() > i) {
            main mainVar = mostCurrent;
            text = mainVar._sf._vvvv5(mainVar._txtprinter6.getText(), 1, i);
            mostCurrent._txtprinter6.setText(BA.ObjectToCharSequence(text));
            mostCurrent._txtprinter6.setSelectionStart(i);
        }
        mostCurrent._lblprintlen6.setText(BA.ObjectToCharSequence(Integer.valueOf(text.length())));
        return "";
    }

    public static String _txtprinter7_textchanged(String str, String str2) throws Exception {
        int i = !_printercolumn ? 16 : 20;
        String text = mostCurrent._txtprinter7.getText();
        if (text.length() > i) {
            main mainVar = mostCurrent;
            text = mainVar._sf._vvvv5(mainVar._txtprinter7.getText(), 1, i);
            mostCurrent._txtprinter7.setText(BA.ObjectToCharSequence(text));
            mostCurrent._txtprinter7.setSelectionStart(i);
        }
        mostCurrent._lblprintlen7.setText(BA.ObjectToCharSequence(Integer.valueOf(text.length())));
        return "";
    }

    public static String _txtprinter8_textchanged(String str, String str2) throws Exception {
        int i = !_printercolumn ? 16 : 20;
        String text = mostCurrent._txtprinter8.getText();
        if (text.length() > i) {
            main mainVar = mostCurrent;
            text = mainVar._sf._vvvv5(mainVar._txtprinter8.getText(), 1, i);
            mostCurrent._txtprinter8.setText(BA.ObjectToCharSequence(text));
            mostCurrent._txtprinter8.setSelectionStart(i);
        }
        mostCurrent._lblprintlen8.setText(BA.ObjectToCharSequence(Integer.valueOf(text.length())));
        return "";
    }
}
