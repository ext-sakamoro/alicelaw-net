// ═══════════════════════════════════════════════════════
// A.L.I.C.E. SDF Metaverse — UE5-Grade + Day/Night + Weather
// ═══════════════════════════════════════════════════════

var MOVE_SPEED=12,FLY_SPEED=8,GRAVITY=14,SENSITIVITY=0.002,EYE_HEIGHT=1.7,RENDER_SCALE=1.0,PI=Math.PI,TAU=PI*2;

var cam={pos:[0,EYE_HEIGHT,15],yaw:0,pitch:0,vy:0,fwd:[0,0,-1],right:[1,0,0],up:[0,1,0]};
var keys={},started=false,locked=false;

document.addEventListener('keydown',function(e){keys[e.key.toLowerCase()]=true;if(e.key===' ')e.preventDefault();});
document.addEventListener('keyup',function(e){keys[e.key.toLowerCase()]=false;});
document.addEventListener('mousemove',function(e){if(!locked)return;cam.yaw+=e.movementX*SENSITIVITY;cam.pitch-=e.movementY*SENSITIVITY;cam.pitch=Math.max(-PI/2+0.05,Math.min(PI/2-0.05,cam.pitch));});

var canvas=document.getElementById('c');
var startEl=document.getElementById('start'),resumeEl=document.getElementById('resume');
var navEl=document.getElementById('nav'),crossEl=document.getElementById('cross');
var hintEl=document.getElementById('hint'),minimapEl=document.getElementById('minimap'),locEl=document.getElementById('loc'),twEl=document.getElementById('tw');
var entEl=document.getElementById('ent'),entFillEl=document.getElementById('entFill'),entLblEl=document.getElementById('entLbl');

function enterLock(){canvas.requestPointerLock();}
startEl.addEventListener('click',function(){startEl.style.opacity='0';setTimeout(function(){startEl.style.display='none';},600);started=true;enterLock();});
resumeEl.addEventListener('click',function(){resumeEl.style.display='none';enterLock();});
document.addEventListener('pointerlockchange',function(){
  locked=document.pointerLockElement===canvas;
  if(started){navEl.style.opacity=locked?'0.4':'1';navEl.style.pointerEvents=locked?'none':'all';crossEl.style.display=locked?'block':'none';hintEl.style.display=locked?'block':'none';minimapEl.style.display=started?'block':'none';locEl.style.display=started?'block':'none';twEl.style.display=started?'block':'none';entEl.style.display=started?'block':'none';if(!locked&&started&&startEl.style.display==='none')resumeEl.style.display='flex';}
});

var locations={lobby:{pos:[0,EYE_HEIGHT,12],yaw:0,pitch:-0.1},services:{pos:[0,EYE_HEIGHT,-24],yaw:0,pitch:0},research:{pos:[24,EYE_HEIGHT,0],yaw:PI/2,pitch:0},stats:{pos:[0,EYE_HEIGHT,24],yaw:PI,pitch:-0.05},contact:{pos:[-24,EYE_HEIGHT,0],yaw:-PI/2,pitch:0}};
var teleport=null;
function startTeleport(name){var tgt=locations[name];if(!tgt)return;teleport={from:{pos:cam.pos.slice(),yaw:cam.yaw,pitch:cam.pitch},to:tgt,t:0};navEl.querySelectorAll('button').forEach(function(b){b.classList.toggle('active',b.dataset.tp===name);});}
function smoothstep(t){return t*t*(3-2*t);}
function lerpAngle(a,b,t){var d=b-a;while(d>PI)d-=2*PI;while(d<-PI)d+=2*PI;return a+d*t;}
function updateTeleport(dt){if(!teleport)return false;teleport.t+=dt*1.2;var s=smoothstep(Math.min(teleport.t,1));cam.pos[0]=teleport.from.pos[0]+(teleport.to.pos[0]-teleport.from.pos[0])*s;cam.pos[1]=teleport.from.pos[1]+(teleport.to.pos[1]-teleport.from.pos[1])*s;cam.pos[2]=teleport.from.pos[2]+(teleport.to.pos[2]-teleport.from.pos[2])*s;cam.yaw=lerpAngle(teleport.from.yaw,teleport.to.yaw,s);cam.pitch=teleport.from.pitch+(teleport.to.pitch-teleport.from.pitch)*s;cam.vy=0;if(teleport.t>=1)teleport=null;return true;}
navEl.querySelectorAll('button').forEach(function(btn){btn.addEventListener('click',function(){startTeleport(btn.dataset.tp);resumeEl.style.display='none';setTimeout(enterLock,80);});});

function updateCameraVectors(){var cp=Math.cos(cam.pitch),sp=Math.sin(cam.pitch),cy=Math.cos(cam.yaw),sy=Math.sin(cam.yaw);cam.fwd=[sy*cp,sp,-cy*cp];cam.right=[cy,0,sy];cam.up=[-sy*sp,cp,cy*sp];}
function updateMovement(dt){var mx=0,mz=0;var fx=Math.sin(cam.yaw),fz=-Math.cos(cam.yaw),rx=Math.cos(cam.yaw),rz=Math.sin(cam.yaw);if(keys['w']||keys['arrowup']){mx+=fx;mz+=fz;}if(keys['s']||keys['arrowdown']){mx-=fx;mz-=fz;}if(keys['a']||keys['arrowleft']){mx-=rx;mz-=rz;}if(keys['d']||keys['arrowright']){mx+=rx;mz+=rz;}var len=Math.sqrt(mx*mx+mz*mz);if(len>0){mx/=len;mz/=len;cam.pos[0]+=mx*MOVE_SPEED*dt;cam.pos[2]+=mz*MOVE_SPEED*dt;}if(keys[' '])cam.vy=FLY_SPEED;else cam.vy-=GRAVITY*dt;cam.pos[1]+=cam.vy*dt;if(cam.pos[1]<EYE_HEIGHT){cam.pos[1]=EYE_HEIGHT;cam.vy=0;}}

// ── Day/Night Cycle ──────────────────────────────────
var DAY_CYCLE=180; // 3 minutes for full day
var dayPhase=0.3;  // start at morning

// ── Weather System ───────────────────────────────────
var WEATHER=[
  {name:'Clear',fog:0,rain:0,dur:55},
  {name:'Fog',fog:1,rain:0,dur:35},
  {name:'Rain',fog:0.3,rain:1,dur:40},
  {name:'Storm',fog:0.4,rain:1,dur:25}
];
var wxIdx=0,wxTimer=0;
var wxFog=0,wxFogTarget=0;
var wxRain=0,wxRainTarget=0;
var lightning=0,lightningTimer=4+Math.random()*6;

// ── Entropy & Destruction System ──────────────────────
var ENT_CALM=65,ENT_DESCENT=10,ENT_DESTRUCT=8,ENT_REBIRTH=6;
var ent={level:0,phase:'calm',timer:0,sh:0,shT:0};
var met={y:300,phase:0,active:false,ix:0,iz:0};
var impactV=0,impactRing=0;
var shk={x:0,y:0};

function updateEntropy(dt){
  ent.timer+=dt;
  if(ent.phase==='calm'){
    ent.level=Math.min(1,ent.level+dt*0.015);
    ent.sh*=0.95;ent.shT=0;
    met.y=300;met.phase=0;met.active=false;
    impactV=Math.max(0,impactV-dt*0.4);
    impactRing=Math.max(0,impactRing-dt*2);
    shk.x*=0.9;shk.y*=0.9;
    if(ent.timer>=ENT_CALM){ent.phase='descent';ent.timer=0;met.active=true;met.ix=(Math.random()-0.5)*6;met.iz=(Math.random()-0.5)*6;}
  }else if(ent.phase==='descent'){
    var t=Math.min(ent.timer/ENT_DESCENT,1);
    met.phase=t;met.y=180*(1-t*t*t);
    ent.level=Math.min(1,0.5+t*0.5);
    ent.shT=t*0.12;ent.sh+=(ent.shT-ent.sh)*Math.min(dt*2,1);
    if(ent.timer>=ENT_DESCENT){ent.phase='destruction';ent.timer=0;impactV=1.0;impactRing=0.5;met.y=0;}
  }else if(ent.phase==='destruction'){
    var t=Math.min(ent.timer/ENT_DESTRUCT,1);
    ent.level=1.0;met.y=Math.max(-5,-t*5);met.phase=1.0;
    impactV=Math.max(0,1-t*0.4);impactRing=Math.min(80,impactRing+dt*14);
    ent.shT=Math.min(1,t*2.5);ent.sh+=(ent.shT-ent.sh)*Math.min(dt*5,1);
    var ss=(1-t)*2.5;shk.x=(Math.random()-0.5)*ss*0.01;shk.y=(Math.random()-0.5)*ss*0.01;
    if(ent.timer>=ENT_DESTRUCT){ent.phase='rebirth';ent.timer=0;}
  }else{
    var t=Math.min(ent.timer/ENT_REBIRTH,1);
    ent.level=Math.max(0,1-t);met.active=t<0.3;met.y=-5-t*20;
    impactV=Math.max(0,impactV-dt*0.35);impactRing=Math.max(0,impactRing-dt*8);
    ent.shT=Math.max(0,1-t*t*2);ent.sh+=(ent.shT-ent.sh)*Math.min(dt*3,1);
    shk.x*=0.92;shk.y*=0.92;
    if(ent.timer>=ENT_REBIRTH){ent.phase='calm';ent.timer=0;ent.level=0;ent.sh=0;ent.shT=0;met.active=false;impactV=0;impactRing=0;shk.x=0;shk.y=0;}
  }
  if(entFillEl)entFillEl.style.width=(ent.level*100)+'%';
  if(entLblEl)entLblEl.textContent='ENTROPY '+Math.round(ent.level*100)+'% '+ent.phase.toUpperCase();
}

function updateEnvironment(dt){
  // Day cycle
  dayPhase=(dayPhase+dt/DAY_CYCLE)%1.0;

  // Weather timer
  wxTimer+=dt;
  if(wxTimer>WEATHER[wxIdx].dur){
    wxTimer=0;
    wxIdx=(wxIdx+1)%WEATHER.length;
    wxFogTarget=WEATHER[wxIdx].fog;
    wxRainTarget=WEATHER[wxIdx].rain;
  }
  // Smooth lerp
  wxFog+=(wxFogTarget-wxFog)*Math.min(dt*0.4,1);
  wxRain+=(wxRainTarget-wxRain)*Math.min(dt*0.3,1);

  // Lightning during storm
  if(WEATHER[wxIdx].name==='Storm'){
    lightningTimer-=dt;
    if(lightningTimer<=0){
      lightning=1.0;
      lightningTimer=2+Math.random()*5;
    }
  }
  lightning*=Math.max(0,1-dt*10); // fast decay

  updateEntropy(dt);

  // Update UI
  var h=Math.floor(dayPhase*24),m=Math.floor((dayPhase*24%1)*60);
  var ts=(h<10?'0':'')+h+':'+(m<10?'0':'')+m;
  var sunH=Math.sin(dayPhase*TAU);
  var phase=sunH>0.15?'DAY':sunH>-0.05?(dayPhase<0.5?'DAWN':'DUSK'):'NIGHT';
  twEl.textContent=ts+' '+phase+'\n'+WEATHER[wxIdx].name;
}

// ── Info Points ────────────────────────────────────────
var infoPoints=[
  {pos:[0,7.5,0],html:'<div class="glass"><h2>Project A.L.I.C.E.</h2><p>Modular AI Agents<br>Autonomous Layered Intelligence</p></div>',range:35},
  {pos:[0,10,-35],html:'<h2>Modules</h2>',range:28},
  {pos:[-6,9.5,-35],html:'<div class="glass"><h3>ALICE-SDF</h3><p>Signed Distance Fields<br>CSG Modeling / Mesh Gen<br>SIMD + Rayon Optimized</p></div>',range:18},
  {pos:[-2,9.5,-35],html:'<div class="glass"><h3>ALICE-Physics</h3><p>Rigid Body Dynamics<br>Fix128 Precision<br>SDF Collision Detection</p></div>',range:18},
  {pos:[2,9.5,-35],html:'<div class="glass"><h3>ALICE-Edge</h3><p>Edge Computing<br>IoT Gateway<br>Latency-Optimized</p></div>',range:18},
  {pos:[6,9.5,-35],html:'<div class="glass"><h3>ALICE-Crypto</h3><p>Post-Quantum Crypto<br>Zero-Knowledge Proofs<br>Secure Communication</p></div>',range:18},
  {pos:[36,8,0],html:'<h2>Research</h2>',range:28},
  {pos:[36,6,-2],html:'<div class="glass"><h3>The Reality Law</h3><p>Spectral Rendering<br>Spacetime Elasticity<br>Deterministic Entropy</p></div>',range:18},
  {pos:[36,4,2],html:'<div class="glass"><h3>AGI Olympics V3</h3><div class="bench">A.L.I.C.E.: <strong>90.2%</strong></div><div class="bench">Gemini 2.5 Pro: 13.3%</div><div class="bench">Claude Sonnet 4.5: 13.3%</div><p style="margin-top:0.4rem;font-size:0.7rem">150MB / 5min / 6.8x accuracy</p></div>',range:18},
  {pos:[0,6,35],html:'<h2>Ecosystem</h2>',range:28},
  {pos:[-6,5,35],html:'<div class="glass"><div class="stat-num">55+</div><p>Rust Crates</p></div>',range:16},
  {pos:[-2,5,35],html:'<div class="glass"><div class="stat-num">24</div><p>Factory Presets</p></div>',range:16},
  {pos:[2,5,35],html:'<div class="glass"><div class="stat-num">6</div><p>Trained Specialists</p></div>',range:16},
  {pos:[6,5,35],html:'<div class="glass"><div class="stat-num">17</div><p>Core Components</p></div>',range:16},
  {pos:[-35,8,0],html:'<h2>Ecosystem</h2>',range:28},
  {pos:[-35,5,0],html:'<div class="glass"><p style="color:#4af">alicelaw.net</p><p style="color:#4af">github.com/ext-sakamoro</p><p style="margin-top:0.4rem;font-size:0.75rem">MIT / AGPL-3.0</p></div>',range:18}
];
var labelsEl=document.getElementById('labels');
infoPoints.forEach(function(ip){var el=document.createElement('div');el.className='label';el.innerHTML=ip.html;el.style.display='none';labelsEl.appendChild(el);ip.el=el;});
function projectLabel(wp){var rx=wp[0]-cam.pos[0],ry=wp[1]-cam.pos[1],rz=wp[2]-cam.pos[2];var z=rx*cam.fwd[0]+ry*cam.fwd[1]+rz*cam.fwd[2];if(z<0.5)return null;var x=rx*cam.right[0]+ry*cam.right[1]+rz*cam.right[2];var y=rx*cam.up[0]+ry*cam.up[1]+rz*cam.up[2];var hw=innerWidth/2,hh=innerHeight/2;return{x:hw+(x/z)*hh,y:hh-(y/z)*hh,dist:z};}
function updateLabels(){for(var i=0;i<infoPoints.length;i++){var ip=infoPoints[i];var dx=ip.pos[0]-cam.pos[0],dy=ip.pos[1]-cam.pos[1],dz=ip.pos[2]-cam.pos[2];var dist=Math.sqrt(dx*dx+dy*dy+dz*dz);if(dist>ip.range){ip.el.style.display='none';continue;}var proj=projectLabel(ip.pos);if(!proj||proj.x<-200||proj.x>innerWidth+200||proj.y<-200||proj.y>innerHeight+200){ip.el.style.display='none';continue;}var alpha=Math.min(1,(ip.range-dist)/(ip.range*0.4));var scale=Math.min(1.2,12/proj.dist);ip.el.style.display='block';ip.el.style.left=proj.x+'px';ip.el.style.top=proj.y+'px';ip.el.style.opacity=alpha;ip.el.style.transform='translate(-50%,-100%) scale('+scale+')';}}
function updateLocationIndicator(){var cx=cam.pos[0],cz=cam.pos[2];var name='Lobby';if(cz<-15)name='Services';else if(cx>15)name='Research';else if(cz>15)name='Stats';else if(cx<-15)name='Contact';locEl.textContent=name+' ['+Math.round(cx)+', '+Math.round(cam.pos[1])+', '+Math.round(cz)+']';}

// ── Minimap ────────────────────────────────────────────
var mmCtx=minimapEl.getContext('2d');
var mmAreas=[{x:0,z:0,c:'#8833ff',l:'L'},{x:0,z:-35,c:'#3366ff',l:'S'},{x:35,z:0,c:'#00aacc',l:'R'},{x:0,z:35,c:'#cc9900',l:'T'},{x:-35,z:0,c:'#cc3388',l:'C'}];
function drawMinimap(){var w=140,h=140,cx=70,cy=70,s=1.5;mmCtx.fillStyle='rgba(0,0,0,0.6)';mmCtx.fillRect(0,0,w,h);mmCtx.strokeStyle='rgba(74,170,255,0.08)';mmCtx.lineWidth=0.5;for(var g=-40;g<=40;g+=10){mmCtx.beginPath();mmCtx.moveTo(cx+g*s,0);mmCtx.lineTo(cx+g*s,h);mmCtx.stroke();mmCtx.beginPath();mmCtx.moveTo(0,cy+g*s);mmCtx.lineTo(w,cy+g*s);mmCtx.stroke();}mmAreas.forEach(function(a){var ax=cx+a.x*s,ay=cy+a.z*s;mmCtx.fillStyle=a.c+'30';mmCtx.beginPath();mmCtx.arc(ax,ay,6,0,PI*2);mmCtx.fill();mmCtx.fillStyle=a.c;mmCtx.beginPath();mmCtx.arc(ax,ay,2.5,0,PI*2);mmCtx.fill();});var px=cx+cam.pos[0]*s,py=cy+cam.pos[2]*s;mmCtx.fillStyle='#fff';mmCtx.beginPath();mmCtx.arc(px,py,3,0,PI*2);mmCtx.fill();mmCtx.strokeStyle='rgba(255,255,255,0.7)';mmCtx.lineWidth=1.5;mmCtx.beginPath();mmCtx.moveTo(px,py);mmCtx.lineTo(px+Math.sin(cam.yaw)*10,py-Math.cos(cam.yaw)*10);mmCtx.stroke();}

// ── WebGL ──────────────────────────────────────────────
var gl=canvas.getContext('webgl',{alpha:false,antialias:false,powerPreference:'high-performance'});
function resize(){canvas.width=Math.floor(innerWidth*RENDER_SCALE);canvas.height=Math.floor(innerHeight*RENDER_SCALE);gl.viewport(0,0,canvas.width,canvas.height);}
resize();window.addEventListener('resize',resize);

var VS='attribute vec2 p;void main(){gl_Position=vec4(p,0,1);}';

// シェーダー非同期読み込み
fetch('alice-universe.glsl').then(function(r){return r.text();}).then(function(FS){
function compileShader(src,type){var s=gl.createShader(type);gl.shaderSource(s,src);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS)){console.error('Shader error:',gl.getShaderInfoLog(s));return null;}return s;}
var vs=compileShader(VS,gl.VERTEX_SHADER),fs=compileShader(FS,gl.FRAGMENT_SHADER);
if(!vs||!fs){startEl.innerHTML='<h1 style="color:#f44">Shader Error</h1><p style="color:#888;font-size:0.9rem">Check browser console for details.</p>';}
var prog=gl.createProgram();gl.attachShader(prog,vs);gl.attachShader(prog,fs);gl.linkProgram(prog);gl.useProgram(prog);
var buf=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buf);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,3,-1,-1,3]),gl.STATIC_DRAW);
var pLoc=gl.getAttribLocation(prog,'p');gl.enableVertexAttribArray(pLoc);gl.vertexAttribPointer(pLoc,2,gl.FLOAT,false,0,0);
var uResL=gl.getUniformLocation(prog,'uRes'),uTimeL=gl.getUniformLocation(prog,'uTime');
var uCamPosL=gl.getUniformLocation(prog,'uCamPos'),uCamFwdL=gl.getUniformLocation(prog,'uCamFwd');
var uCamRightL=gl.getUniformLocation(prog,'uCamRight'),uCamUpL=gl.getUniformLocation(prog,'uCamUp');
var uDayPhaseL=gl.getUniformLocation(prog,'uDayPhase');
var uWxFogL=gl.getUniformLocation(prog,'uWxFog');
var uWxRainL=gl.getUniformLocation(prog,'uWxRain');
var uLightningL=gl.getUniformLocation(prog,'uLightning');
var uEntropyL=gl.getUniformLocation(prog,'uEntropy');
var uShatterL=gl.getUniformLocation(prog,'uShatter');
var uMeteorYL=gl.getUniformLocation(prog,'uMeteorY');
var uMeteorActiveL=gl.getUniformLocation(prog,'uMeteorActive');
var uMeteorImpactL=gl.getUniformLocation(prog,'uMeteorImpact');
var uImpactL=gl.getUniformLocation(prog,'uImpact');
var uImpactRingL=gl.getUniformLocation(prog,'uImpactRing');
var uShakeL=gl.getUniformLocation(prog,'uShake');
var uMaxDistL=gl.getUniformLocation(prog,'uMaxDist');
var uTimeDilationL=gl.getUniformLocation(prog,'uTimeDilation');

// ── Path Ω: Spacetime Elasticity (RENDER_SCALE=1.0 always) ──
var ftEMA=16,ftAlpha=0.15;
var stMaxDist=95.0,stTimeDilation=1.0,stGameTime=-1;
function pathOmegaSpacetime(dtMs){
  ftEMA+=(dtMs-ftEMA)*ftAlpha;
  // Light-speed throttling: shrink max ray distance when GPU heavy
  if(ftEMA>20)stMaxDist=Math.max(30.0,stMaxDist-2.0);
  else if(ftEMA<14)stMaxDist=Math.min(95.0,stMaxDist+1.0);
  // Time dilation: heavy frames → slow-motion effect
  if(ftEMA>22)stTimeDilation=Math.max(0.25,stTimeDilation-0.03);
  else if(ftEMA<16)stTimeDilation=Math.min(1.0,stTimeDilation+0.02);
}

var lastTime=0;
function frame(time){
  var dtMs=time-lastTime;
  var dt=Math.min(dtMs/1000,0.1);lastTime=time;
  if(started){
    pathOmegaSpacetime(dtMs);
    if(stGameTime<0)stGameTime=time*0.001;
    dt*=stTimeDilation;
    stGameTime+=dt;
    var isTp=updateTeleport(dt);
    if(!isTp&&locked)updateMovement(dt);
    updateCameraVectors();
    updateEnvironment(dt);
    cam.pos[0]=Math.max(-60,Math.min(60,cam.pos[0]));
    cam.pos[2]=Math.max(-60,Math.min(60,cam.pos[2]));
    cam.pos[1]=Math.max(EYE_HEIGHT,Math.min(30,cam.pos[1]));
    gl.uniform2f(uResL,canvas.width,canvas.height);
    gl.uniform1f(uTimeL,stGameTime);
    gl.uniform1f(uMaxDistL,stMaxDist);
    gl.uniform1f(uTimeDilationL,stTimeDilation);
    gl.uniform3f(uCamPosL,cam.pos[0],cam.pos[1],cam.pos[2]);
    gl.uniform3f(uCamFwdL,cam.fwd[0],cam.fwd[1],cam.fwd[2]);
    gl.uniform3f(uCamRightL,cam.right[0],cam.right[1],cam.right[2]);
    gl.uniform3f(uCamUpL,cam.up[0],cam.up[1],cam.up[2]);
    gl.uniform1f(uDayPhaseL,dayPhase);
    gl.uniform1f(uWxFogL,wxFog);
    gl.uniform1f(uWxRainL,wxRain);
    gl.uniform1f(uLightningL,lightning);
    gl.uniform1f(uEntropyL,ent.level);
    gl.uniform1f(uShatterL,ent.sh);
    gl.uniform1f(uMeteorYL,met.y);
    gl.uniform1f(uMeteorActiveL,met.active?1.0:0.0);
    gl.uniform2f(uMeteorImpactL,met.ix,met.iz);
    gl.uniform1f(uImpactL,impactV);
    gl.uniform1f(uImpactRingL,impactRing);
    gl.uniform2f(uShakeL,shk.x,shk.y);
    gl.drawArrays(gl.TRIANGLES,0,3);
    updateLabels();updateLocationIndicator();drawMinimap();
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
});
