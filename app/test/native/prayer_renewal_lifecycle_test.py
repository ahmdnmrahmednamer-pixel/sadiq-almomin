"""Compile and exercise actual native coordinator with JVM API doubles.

Not an Android instrumented/device test. Requires a Kotlin compiler classpath
in KOTLIN_COMPILER_CP (or a cached Gradle Kotlin compiler), and JAVA_HOME/java.
"""
from pathlib import Path
import subprocess, os, tempfile
temporary=tempfile.TemporaryDirectory(prefix='prayer-renewal-native-')
root=Path(temporary.name)
files={
'Context.kt':'''package android.content
open class Context { val applicationContext get()=this; fun <T> getSystemService(cls: Class<T>):T=cls.cast(android.app.job.JobScheduler.instance) }
class ComponentName(context:Context, cls:Class<*>)
''',
'Job.kt':'''package android.app.job
import android.content.*
class JobParameters
open class JobService:Context(){ val finished=mutableListOf<Boolean>();open fun onStartJob(p:JobParameters)=false;open fun onStopJob(p:JobParameters)=false;open fun onDestroy(){};fun jobFinished(p:JobParameters,retry:Boolean){finished.add(retry)} }
class JobScheduler {companion object {const val RESULT_SUCCESS=1;val instance=JobScheduler()};var calls=0;var request:JobInfo?=null;fun getPendingJob(id:Int)=request;fun schedule(info:JobInfo):Int{calls++;request=info;return 1}}
class JobInfo(val persisted:Boolean,val period:Long){class Builder(id:Int,name:ComponentName){var persisted=false;var period=0L;fun setPersisted(v:Boolean)=apply{persisted=v};fun setPeriodic(v:Long)=apply{period=v};fun build()=JobInfo(persisted,period)}}
''',
'Handler.kt':'''package android.os
class Looper {companion object{fun getMainLooper()=Looper()}}
class Handler(l:Looper){companion object {val posts=mutableListOf<Runnable>();val timers=mutableListOf<Runnable>();fun drain(){while(posts.isNotEmpty())posts.removeAt(0).run()};fun timeout(){val all=timers.toList();timers.clear();all.forEach{it.run()}}};fun post(r:Runnable){posts.add(r)};fun postDelayed(r:Runnable,ms:Long){check(ms==90000L);timers.add(r)};fun removeCallbacks(r:Runnable){timers.remove(r)}}
''',
'Injector.kt':'''package io.flutter
import android.content.Context
class FlutterInjector {companion object{fun instance()=FlutterInjector()};fun flutterLoader()=Loader()}
class Loader {fun startInitialization(c:Context){};fun ensureInitializationComplete(c:Context,x:Any?){};fun findAppBundlePath()="bundle"}
''',
'Engine.kt':'''package io.flutter.embedding.engine
import android.content.Context
import io.flutter.embedding.engine.dart.DartExecutor
class FlutterEngine(c:Context){companion object{var live=0;var destroyed=0};init{live++};val dartExecutor=DartExecutor();fun destroy(){live--;destroyed++}}
''',
'Executor.kt':'''package io.flutter.embedding.engine.dart
class DartExecutor{val binaryMessenger=Any();fun executeDartEntrypoint(e:DartEntrypoint){check(e.library=="package:almomin/core/notifications/prayer_renewal.dart");check(e.entry=="prayerRenewalMain")};class DartEntrypoint(val bundle:String,val library:String,val entry:String)}
''',
'Channel.kt':'''package io.flutter.plugin.common
class MethodCall(val method:String,val arguments:Any?)
class MethodChannel(val messenger:Any,val name:String){companion object{val channels=mutableListOf<MethodChannel>()};init{channels.add(this)};var handler:((MethodCall,Result)->Unit)?=null;var pending:Result?=null;var invoked:String?=null;fun setMethodCallHandler(h:((MethodCall,Result)->Unit)?){handler=h};fun invokeMethod(m:String,args:Any?,r:Result){invoked=m;pending=r};interface Result {fun success(result:Any?);fun error(code:String,message:String?,details:Any?);fun notImplemented()}}
''',
'Test.kt':'''package org.almomin.app
import android.app.job.*
import android.content.Context
import android.os.Handler
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.*
fun checkCase(name:String, body:()->Unit){body();println("PASS $name")}
fun main(){
 val context=Context()
 checkCase("persistent six-hour checkpoint is registered once"){
  check(PrayerRenewalCoordinator.register(context));check(PrayerRenewalCoordinator.register(context))
  val scheduler=JobScheduler.instance;check(scheduler.calls==1);check(scheduler.request!!.persisted);check(scheduler.request!!.period==21600000L)
 }
 checkCase("headless start yields promptly, then creates one engine"){
  val job=PrayerRenewalJobService();check(job.onStartJob(JobParameters()));check(FlutterEngine.live==0)
  Handler.drain();check(FlutterEngine.live==1)
  val channel=MethodChannel.channels.last();var reply=false
  channel.handler!!(MethodCall("finish",true),object:MethodChannel.Result{override fun success(result:Any?){reply=true};override fun error(c:String,m:String?,d:Any?){};override fun notImplemented(){}})
  check(reply);check(FlutterEngine.live==1);Handler.drain();check(FlutterEngine.live==0);check(job.finished==listOf(false));check(Handler.timers.isEmpty())
 }
 checkCase("timeout destroys only headless engine and requests retry"){
  val job=PrayerRenewalJobService();job.onStartJob(JobParameters());Handler.drain();check(FlutterEngine.live==1);Handler.timeout();check(FlutterEngine.live==0);check(job.finished==listOf(true));check(PrayerRenewalCoordinator.job==null)
 }
 checkCase("Android stop cleans ownership without jobFinished duplicate"){
  val job=PrayerRenewalJobService();job.onStartJob(JobParameters());Handler.drain();check(job.onStopJob(JobParameters()));check(FlutterEngine.live==0);check(job.finished.isEmpty());Handler.timeout();check(job.finished.isEmpty())
 }
 checkCase("stop before posted engine creation cannot create a late isolate"){
  val job=PrayerRenewalJobService();job.onStartJob(JobParameters());job.onStopJob(JobParameters());Handler.drain();check(FlutterEngine.live==0)
 }
 checkCase("foreground handoff destroys headless engine before UI attaches"){
  val job=PrayerRenewalJobService();job.onStartJob(JobParameters());Handler.drain();check(FlutterEngine.live==1)
  job.interruptForForeground();check(FlutterEngine.live==0)
  val ui=FlutterEngine(context);PrayerRenewalCoordinator.attach(ui,context);check(FlutterEngine.live==1);check(job.finished==listOf(true))
  val next=PrayerRenewalJobService();next.onStartJob(JobParameters());Handler.drain();check(FlutterEngine.live==1)
  val channel=PrayerRenewalCoordinator.foreground!!;check(channel.invoked=="renew");channel.pending!!.success(true);check(next.finished==listOf(false));check(FlutterEngine.live==1)
  PrayerRenewalCoordinator.detach();ui.destroy()
 }
 checkCase("late foreground reply after stop cannot finish another job"){
  val ui=FlutterEngine(context);PrayerRenewalCoordinator.attach(ui,context)
  val job=PrayerRenewalJobService();job.onStartJob(JobParameters());Handler.drain();val callback=PrayerRenewalCoordinator.foreground!!.pending!!
  job.onStopJob(JobParameters());callback.success(true);check(job.finished.isEmpty());check(FlutterEngine.live==1)
  PrayerRenewalCoordinator.detach();ui.destroy()
 }
 checkCase("foreground error requests retry without destroying UI engine"){
  val ui=FlutterEngine(context);PrayerRenewalCoordinator.attach(ui,context)
  val job=PrayerRenewalJobService();job.onStartJob(JobParameters());Handler.drain();PrayerRenewalCoordinator.foreground!!.pending!!.error("fixture",null,null)
  check(job.finished==listOf(true));check(FlutterEngine.live==1);PrayerRenewalCoordinator.detach();ui.destroy()
 }
 checkCase("service destruction clears headless isolate and timeout"){
  val job=PrayerRenewalJobService();job.onStartJob(JobParameters());Handler.drain();job.onDestroy();check(FlutterEngine.live==0);check(Handler.timers.isEmpty());check(PrayerRenewalCoordinator.job==null)
 }
}
'''
}
for name,content in files.items():(root/name).write_text(content)
compiler_cp=os.environ.get('KOTLIN_COMPILER_CP')
if compiler_cp is None:
    compiler=next((Path.home()/'.gradle/wrapper/dists').glob('gradle-*-all/*/gradle-*/lib/kotlin-compiler-embeddable-*.jar'),None)
    if compiler is None: raise SystemExit('Set KOTLIN_COMPILER_CP to Kotlin compiler library directory/*')
    compiler_cp=str(compiler.parent/'*')
libdir=Path(compiler_cp.removesuffix('*'))
stdlib=next(libdir.glob('kotlin-stdlib-*.jar'))
java=str(Path(os.environ['JAVA_HOME'])/'bin/java') if 'JAVA_HOME' in os.environ else 'java'
source=Path(__file__).resolve().parents[2]/'android/app/src/main/kotlin/org/almomin/app/PrayerRenewalJobService.kt'
subprocess.run([java,'-cp',compiler_cp,'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler','-no-stdlib','-no-reflect','-classpath',str(stdlib),'-d',str(root/'classes'),str(source),*map(str,root.glob('*.kt'))],check=True)
subprocess.run([java,'-cp',str(root/'classes')+os.pathsep+str(stdlib),'org.almomin.app.TestKt'],check=True)
