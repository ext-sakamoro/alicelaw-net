precision highp float;
uniform vec2 uRes;
uniform float uTime;
uniform vec3 uCamPos,uCamFwd,uCamRight,uCamUp;
uniform float uDayPhase;
uniform float uWxFog;
uniform float uWxRain;
uniform float uLightning;
uniform float uEntropy;
uniform float uShatter;
uniform float uMeteorY;
uniform float uMeteorActive;
uniform vec2 uMeteorImpact;
uniform float uImpact;
uniform float uImpactRing;
uniform vec2 uShake;
uniform float uMaxDist;
uniform float uTimeDilation;

#define PI 3.14159265
#define TAU 6.28318530
#define SAT(x) clamp(x,0.0,1.0)

// ═══ Noise ═══
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float hash3(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float vnoise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
float vnoise3(vec3 p){vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);float n00=mix(hash3(i),hash3(i+vec3(1,0,0)),f.x);float n10=mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x);float n01=mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x);float n11=mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x);return mix(mix(n00,n10,f.y),mix(n01,n11,f.y),f.z);}
float fbm(vec2 p){float v=0.0,a=0.5;mat2 r=mat2(0.8,0.6,-0.6,0.8);for(int i=0;i<5;i++){v+=a*vnoise(p);p=r*p*2.1;a*=0.48;}return v;}
float fbm3(vec3 p){float v=0.0,a=0.5;for(int i=0;i<4;i++){v+=a*vnoise3(p);p=p*2.15+vec3(1.7,3.2,2.8);a*=0.45;}return v;}

// ═══ SDF Primitives ═══
float sdBox(vec3 p,vec3 b){vec3 q=abs(p)-b;return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0);}
float sdRoundBox(vec3 p,vec3 b,float r){vec3 q=abs(p)-b+r;return length(max(q,0.0))+min(max(q.x,max(q.y,q.z)),0.0)-r;}
float sdSphere(vec3 p,float r){return length(p)-r;}
float sdTorus(vec3 p,vec2 t){vec2 q=vec2(length(p.xz)-t.x,p.y);return length(q)-t.y;}
float sdOctahedron(vec3 p,float s){p=abs(p);return(p.x+p.y+p.z-s)*0.57735027;}
float sdCylinder(vec3 p,float h,float r){vec2 d=abs(vec2(length(p.xz),p.y))-vec2(r,h);return min(max(d.x,d.y),0.0)+length(max(d,0.0));}
float sdGyroid(vec3 p,float sc,float th){float invSc=1.0/sc;p*=sc;return abs(dot(sin(p),cos(p.zxy)))*invSc-th;}
float smin(float a,float b,float k){float invK=1.0/k;float h=max(k-abs(a-b),0.0);return min(a,b)-h*h*0.25*invK;}
mat2 rot(float a){float c=cos(a),s=sin(a);return mat2(c,-s,s,c);}
float disp(vec3 p){return sin(p.x*2.1+p.z*0.7)*sin(p.y*1.3+p.z*0.9)*0.5+sin(p.z*3.2-p.x*1.1)*sin(p.y*2.7)*0.25;}

// ═══ VFX Foundation (ALICE-VFX Recipe) ═══
// Blackbody radiation — temperature(K) to physically correct color
vec3 blackbody(float K){
  float t=K*0.01;
  float hi=step(66.0,t);float lo=1.0-hi;
  float r=mix(1.0,SAT(1.292936*inversesqrt(max(t-55.0,0.001))-0.16),hi);
  float g=mix(SAT(0.39008*log(max(t,1.0))-0.63184),SAT(1.129891*inversesqrt(max(t-50.0,0.001))-0.15),hi);
  float warm=step(19.0,t);
  float b=mix(SAT(0.54321*log(max(t-10.0,1.0))-1.19625)*warm,1.0,hi);
  return vec3(r,g,b);
}
// Spectral rendering — CIE 1931 2-deg observer approximation (wavelength nm → linear RGB)
vec3 spectralToRGB(float lambda){
  // Gaussian fit to CIE xyz color matching functions
  float x=1.056*exp(-0.5*pow((lambda-599.8)*0.0244,2.0))+0.362*exp(-0.5*pow((lambda-442.0)*0.0624,2.0))-0.065*exp(-0.5*pow((lambda-501.1)*0.049,2.0));
  float y=0.821*exp(-0.5*pow((lambda-568.8)*0.0213,2.0))+0.286*exp(-0.5*pow((lambda-530.9)*0.0613,2.0));
  float z=1.217*exp(-0.5*pow((lambda-437.0)*0.0845,2.0))+0.681*exp(-0.5*pow((lambda-459.0)*0.0385,2.0));
  // CIE XYZ → sRGB linear (D65)
  return vec3(3.2406*x-1.5372*y-0.4986*z,-0.9689*x+1.8758*y+0.0415*z,0.0557*x-0.2040*y+1.0570*z);
}
// Spectral integration — evaluate blackbody S(lambda) over visible range (380-720nm, 8 samples)
vec3 spectralBlackbody(float K){
  vec3 acc=vec3(0);
  float invK=1.0/(K+0.001);
  for(int i=0;i<8;i++){
    float lambda=380.0+float(i)*48.57; // 380 to 720nm
    // Planck's law (simplified): S(λ) ∝ λ^-5 / (exp(hc/λkT) - 1)
    float lm=lambda*1e-3; // micro-scale for numerical stability
    float x=1.4388e3*invK/(lambda+0.001); // hc/kT * 1/lambda (in nm)
    float planck=1.0/(lm*lm*lm*lm*lm*(exp(min(x,80.0))-1.0)+0.001);
    acc+=spectralToRGB(lambda)*planck;
  }
  return max(acc*0.000125,vec3(0)); // normalize
}
// Rayleigh spectral sky — wavelength-dependent λ^-4 scattering
vec3 rayleighSpectral(float mu,float am,float densR,vec3 extR){
  vec3 acc=vec3(0);
  for(int i=0;i<6;i++){
    float lambda=400.0+float(i)*60.0; // 400-700nm
    float scatter=1.0/(lambda*lambda*lambda*lambda)*1e10; // λ^-4
    float phR=0.059683*(1.0+mu*mu);
    vec3 rgb=spectralToRGB(lambda);
    acc+=rgb*scatter*phR*am*densR;
  }
  return max(acc*extR*0.008,vec3(0));
}
// Micro-FBM — nanoscale thermal vibration displacement for atomic-level surface detail
vec3 microNormal(vec3 p,vec3 n,float freq,float amp){
  vec2 e=vec2(0.001,0);
  float d0=vnoise3(p*freq);
  float dx=vnoise3((p+e.xyy)*freq)-d0;
  float dy=vnoise3((p+e.yxy)*freq)-d0;
  float dz=vnoise3((p+e.yyx)*freq)-d0;
  return normalize(n+vec3(dx,dy,dz)*(amp/(e.x+0.0001)));
}
// Analytic bloom — SDF distance-based glow (no blur pass)
vec3 aBloom(float d,vec3 gc,float intensity,float falloff){
  return gc*exp(-abs(d)*falloff)*intensity;
}
// Domain warp — 2-pass analytic spatial distortion
vec3 dWarp(vec3 p,float t,float intensity){
  float fx=sin(p.y*1.7+t*0.3);float fy=cos(p.z*1.3+t*0.5);float fz=sin(p.x*2.1+t*0.4);
  float gx=cos(fy*2.3+fx*1.1);float gy=sin(fz*1.9+fy*0.7);float gz=cos(fx*1.5+fz*1.3);
  return p+vec3(gx,gy,gz)*intensity;
}
// Dielectric Breakdown Model — fractal space-folding discharge
float dbmDischarge(vec3 p,vec3 src,float charge,float t){
  vec3 dir=normalize(p-src);float dist=length(p-src);
  float discharge=0.0;float amp=1.0;vec3 q=p;
  for(int i=0;i<6;i++){
    q=abs(q)-dir*0.5*amp;
    float ca=cos(charge*float(i)+t);float sa=sin(charge*float(i)+t);
    q.xy=vec2(q.x*ca-q.y*sa,q.x*sa+q.y*ca);
    discharge+=(1.0/(length(q.xz)+0.01))*amp;
    amp*=0.5;
  }
  return discharge*exp(-dist*0.5)*charge;
}

// ═══ Interior Mapping (pseudo-rooms behind walls) ═══
vec3 interiorMap(vec3 p,float scale){
  vec3 uv=fract(p*scale);
  vec3 fp=abs(uv-0.5);
  float wall=smoothstep(0.02,0.0,min(fp.x,fp.z));
  float flr=smoothstep(0.02,0.0,fp.y);
  float room=hash(floor(p.xz*scale));
  float lit=step(0.6,room);
  vec3 col=mix(vec3(0.005,0.01,0.025),vec3(0.02,0.06,0.15),lit);
  col+=vec3(0.08,0.25,0.65)*wall*lit*0.3;
  col+=vec3(0.04,0.12,0.3)*flr*0.15;
  return col;
}

// ═══ Materials ═══
struct Mat{vec3 albedo;float metallic;float roughness;vec3 emission;float sss;};

Mat getMat(float id,vec3 p){
  Mat m;m.emission=vec3(0);m.sss=0.0;
  if(id<0.5){
    float tile=fbm(p.xz*0.25)*0.06;float micro=vnoise(p.xz*12.0)*0.015;
    m.albedo=vec3(0.025+tile,0.03+tile,0.048+tile)+micro;m.metallic=0.08;m.roughness=0.18+tile*0.2;
    vec2 g=abs(fract(p.xz*0.5)-0.5);float line=1.0-smoothstep(0.0,0.012,min(g.x,g.y));
    vec2 sg=abs(fract(p.xz*2.0)-0.5);float sline=1.0-smoothstep(0.0,0.006,min(sg.x,sg.y));
    float pathGlow=max(smoothstep(1.0,0.0,abs(p.x)),smoothstep(1.0,0.0,abs(p.z)));
    float pathPulse=sin(length(p.xz)*0.3-uTime*1.5)*0.3+0.7;
    m.emission=vec3(0.06,0.35,0.7)*line*0.55+vec3(0.03,0.18,0.4)*sline*0.18+vec3(0.04,0.35,0.65)*pathGlow*0.25*pathPulse;
    float puddle=smoothstep(3.0,0.5,length(fract(p.xz*0.08)*12.5-6.25));
    m.roughness*=mix(1.0,0.03,puddle*0.4);
    // Rain makes floor wetter
    m.roughness*=mix(1.0,0.04,uWxRain*0.55);
    // Rain splash ripples on floor
    if(uWxRain>0.01){
      // 3 layers of expanding concentric ripples at pseudo-random positions
      float splash=0.0;
      for(int i=0;i<3;i++){
        float fi=float(i);
        vec2 cell=floor(p.xz*1.5+fi*7.3);
        vec2 rpos=cell+vec2(hash(cell+fi*13.7),hash(cell+fi*31.1+5.0));
        float dist=length(p.xz*1.5-rpos);
        float phase=fract(uTime*(1.2+fi*0.3)+hash(cell)*6.28);
        float ring=1.0-smoothstep(0.0,0.04,abs(dist-phase*1.8));
        float fade=(1.0-phase)*(1.0-phase);
        splash+=ring*fade;
      }
      splash=min(splash,1.0)*uWxRain;
      // Ripples disturb roughness locally
      m.roughness=mix(m.roughness,0.01,splash*0.6);
      // Tiny white splash highlight
      m.emission+=vec3(0.15,0.25,0.45)*splash*0.35;
    }
  }else if(id<1.5){
    // Energy Orb — branchless zone color via step masks
    float zN=step(p.z,-20.0);float xP=step(20.0,p.x)*(1.0-zN);float zP=step(20.0,p.z)*(1.0-zN)*(1.0-xP);float xN=step(p.x,-20.0)*(1.0-zN)*(1.0-xP)*(1.0-zP);float ctr=1.0-zN-xP-zP-xN;
    vec3 oC1=vec3(0.1,0.25,1.0)*zN+vec3(0.0,0.55,0.7)*xP+vec3(0.85,0.55,0.05)*zP+vec3(0.7,0.06,0.4)*xN+vec3(0.4,0.06,0.7)*ctr;
    vec3 oC2=vec3(0.35,0.65,1.5)*zN+vec3(0.15,0.85,1.0)*xP+vec3(1.0,0.8,0.2)*zP+vec3(1.0,0.2,0.7)*xN+vec3(0.6,0.2,1.0)*ctr;
    // Domain warp: 2-pass analytic distortion for organic plasma surface
    vec3 wp=dWarp(p,uTime*0.8,0.6);
    float pl=fbm3(wp*2.0+uTime*0.5);float pu=sin(uTime*2.5+pl*5.0)*0.5+0.5;
    m.albedo=mix(oC1,oC2,pl)*0.2;m.metallic=0.1;m.roughness=0.04;
    m.emission=mix(oC1,oC2,pl)*(1.8+pu*1.2);
    // Dielectric Breakdown Model: fractal space-folding discharge
    float arc=dbmDischarge(p,p-vec3(0,0.5,0),1.5+sin(uTime*1.8)*0.5,uTime*2.0);
    m.emission+=vec3(1.0,1.0,1.2)*SAT(arc-0.5)*8.0;
    m.emission+=mix(oC1,oC2,0.5)*0.4;m.sss=0.6;
  }else if(id<2.5){
    float brush=vnoise(vec2(p.y*40.0,atan(p.x,p.z)*12.0))*0.08;
    m.albedo=vec3(0.74,0.74,0.76)+brush;m.metallic=0.97;m.roughness=0.06+brush*0.4;
    m.emission=vec3(0.04,0.18,0.4)*0.12;
    // Fractal folding micro-detail
    vec3 fp2=abs(fract(p*8.0)-0.5);float fold2=min(fp2.x,min(fp2.y,fp2.z));
    m.roughness+=smoothstep(0.02,0.0,fold2)*0.15;
    m.emission+=vec3(0.02,0.08,0.2)*smoothstep(0.01,0.0,fold2)*0.3;
  }else if(id<3.5){
    m.albedo=vec3(0.015,0.03,0.07);m.metallic=0.04;m.roughness=0.015;m.sss=0.55;
    float scan=smoothstep(0.4,0.5,sin(p.y*10.0+uTime*2.0)*0.5+0.5);
    float data=step(0.97,hash(floor(vec2(p.x*4.0,p.y*20.0-uTime*3.0))));
    float edge=1.0-smoothstep(0.0,0.12,abs(fract(p.y*0.2)-0.5));
    m.emission=vec3(0.08,0.25,0.75)*0.35+vec3(0.04,0.12,0.45)*scan*0.35+vec3(0.25,0.6,1.0)*data*0.9+vec3(0.06,0.2,0.65)*edge*0.25;
    // Interior mapping — pseudo-rooms behind glass panels
    vec3 iRoom=interiorMap(p,1.2);m.emission+=iRoom*0.6;
  }else if(id<4.5){
    m.albedo=vec3(0.02,0.055,0.075)+vnoise3(p*2.0)*0.015;m.metallic=0.12;m.roughness=0.04;m.sss=0.35;
    m.emission=vec3(0.0,0.38,0.65)*0.28+vec3(0.0,0.5,0.85)*(sin(p.y*4.0)*0.5+0.5)*0.12;
    vec3 iRoom2=interiorMap(p,0.8);m.emission+=iRoom2*0.4;
  }else if(id<5.5){
    float d=vnoise3(p*18.0);m.albedo=vec3(0.88,0.68,0.22)+d*0.04;m.metallic=0.94;m.roughness=0.22+d*0.1;
  }else if(id<6.5){
    m.albedo=vec3(0.95,0.82,0.35);m.metallic=0.99;m.roughness=0.015;
    float sp=pow(max(sin(p.x*20.0+uTime*4.0)*sin(p.y*20.0-uTime*3.0)*sin(p.z*20.0+uTime*2.0),0.0),8.0);
    m.emission=vec3(0.8,0.55,0.1)*(0.35+0.25*sin(uTime*3.0))+vec3(1.0,0.9,0.6)*sp*0.5;
  }else if(id<7.5){
    float pl=vnoise3(p*4.0+vec3(uTime*0.6,uTime*0.4,uTime*0.8));
    m.albedo=vec3(0.2,0.02,0.12);m.metallic=0.45;m.roughness=0.08;
    m.emission=mix(vec3(1.0,0.1,0.55),vec3(0.35,0.1,1.0),pl)*(0.55+0.35*sin(uTime*2.5+pl*5.0));
  }else if(id<8.5){
    float pu=sin(uTime*3.0+length(p)*2.5)*0.5+0.5;
    m.albedo=vec3(0.12,0.35,0.55);m.metallic=0.2;m.roughness=0.05;
    m.emission=vec3(0.35,0.7,1.3)*(0.5+pu*0.5);m.sss=0.85;
  }else if(id<9.5){
    float d=vnoise3(p*6.0)*0.04;float md=vnoise3(p*40.0)*0.002;m.albedo=vec3(0.04+d+md,0.042+d+md,0.055+d+md);m.metallic=0.88;m.roughness=0.28+md*2.0;
    m.emission=vec3(0.02,0.1,0.22)*0.12;
  }else if(id<10.5){
    float md10=vnoise3(p*40.0)*0.002;m.albedo=vec3(0.68+md10,0.7+md10,0.72+md10);m.metallic=0.98;m.roughness=0.04+abs(md10)*3.0;m.emission=vec3(0.04,0.18,0.42)*0.18;
    // Fractal folding ornament
    vec3 fp10=abs(fract(p*12.0)-0.5);float fold10=min(fp10.x,min(fp10.y,fp10.z));
    m.emission+=vec3(0.03,0.12,0.3)*smoothstep(0.015,0.0,fold10)*0.25;
  }else if(id<11.5){
    m.albedo=vec3(0.08,0.15,0.25);m.metallic=0.0;m.roughness=0.5;
    m.emission=vec3(0.15,0.55,1.0)*(0.85+0.15*sin(uTime*5.0+p.y*2.0));
  }else if(id<12.5){
    m.albedo=vec3(0.01,0.04,0.06);m.metallic=0.05;m.roughness=0.08;m.sss=0.8;
    m.emission=vec3(0.0,0.55,0.9)*0.5*(sin(p.y*2.0+uTime*1.5)*0.5+0.5)+vec3(0.1,0.3,0.7)*0.2;
  }else if(id<14.5){
    // Meteor core — blackbody radiation (8000K core → 3000K surface)
    float plasma=fbm3(p*0.8+vec3(uTime*0.5,uTime*2.5,uTime*0.8));
    float vortex=fbm3(p*1.5+vec3(sin(uTime*0.3)*3.0,uTime*4.0,cos(uTime*0.2)*2.0));
    float coreTemp=mix(8000.0,3000.0,plasma); // temperature gradient
    m.albedo=vec3(0.02);m.metallic=0.0;m.roughness=0.95;
    vec3 bbCol=blackbody(coreTemp);
    m.emission=bbCol*mix(12.0,20.0,plasma)+blackbody(12000.0)*pow(max(vortex,0.0),2.0)*8.0;
  }else if(id<15.5){
    // Meteor tail — blackbody cooling gradient (6000K→1500K)
    float streak=fbm3(p*vec3(4.0,0.2,4.0)+vec3(0,uTime*8.0,0));
    float tailTemp=mix(6000.0,1500.0,streak);
    m.albedo=vec3(0.01);m.metallic=0.0;m.roughness=1.0;m.sss=1.0;
    vec3 tailBB=blackbody(tailTemp);
    float pulse=pow(max(sin(p.y*0.5+uTime*3.0)*0.5+0.5,0.0),2.0);
    m.emission=tailBB*mix(8.0,15.0,1.0-streak)+blackbody(4500.0)*pulse*4.0;
  }else if(id<16.5){
    m.albedo=vec3(0.96,0.97,1.0);m.metallic=0.02;m.roughness=0.008;m.sss=0.85;
    m.emission=vec3(0.04,0.08,0.15)*0.08;
    float sh=max(uShatter,(uEntropy-0.5)*0.15);
    if(sh>0.005){vec3 fr=fract(p*2.5);vec3 df=min(fr,1.0-fr);float e=min(df.x,min(df.y,df.z));float ck=smoothstep(0.12*sh,0.0,e);m.emission+=mix(vec3(1.5,0.6,0.12),vec3(0.3,0.6,1.2),1.0-uEntropy)*ck*sh*6.0;m.albedo*=1.0-ck*0.3;}
  }else if(id<17.5){
    // Energy Ring — branchless zone color via step masks
    float rzN=step(p.z,-20.0);float rxP=step(20.0,p.x)*(1.0-rzN);float rzP=step(20.0,p.z)*(1.0-rzN)*(1.0-rxP);float rxN=step(p.x,-20.0)*(1.0-rzN)*(1.0-rxP)*(1.0-rzP);float rctr=1.0-rzN-rxP-rzP-rxN;
    vec3 rC=vec3(0.25,0.5,1.5)*rzN+vec3(0.1,0.8,0.9)*rxP+vec3(1.0,0.7,0.15)*rzP+vec3(0.9,0.15,0.55)*rxN+vec3(0.5,0.15,1.0)*rctr;
    float flow=fbm3(p*6.0+vec3(uTime*2.5));
    m.albedo=rC*0.12;m.metallic=0.8;m.roughness=0.02;
    m.emission=rC*(2.5+flow*2.0);
    float spark=pow(max(vnoise3(p*20.0+uTime*5.0),0.0),10.0);
    m.emission+=vec3(1.0,1.0,1.2)*spark*8.0;
  }else if(id<18.5){
    // Debris — fractured concrete + thermal glow (Law of Entropy: phase change)
    float heat=SAT(uShatter*2.0-0.3);
    float grain=vnoise3(p*12.0)*0.08;
    m.albedo=vec3(0.06+grain,0.055+grain,0.05+grain);m.metallic=0.35;m.roughness=0.65+grain;
    m.emission=blackbody(mix(1200.0,3500.0,heat))*heat*4.0;
  }else{
    m.albedo=vec3(0.25,0.45,0.65);m.metallic=0.0;m.roughness=0.5;m.emission=vec3(0.15,0.45,0.9)*0.45;m.sss=1.0;
  }
  return m;
}

// ═══ Physical Destruction (Law D-2) ═══
vec3 voronoi2(vec2 p){
  vec2 n=floor(p);vec2 f=fract(p);
  float md=8.0,md2=8.0;vec2 mg=vec2(0);
  for(int j=-1;j<=1;j++)for(int i=-1;i<=1;i++){
    vec2 g=vec2(float(i),float(j));
    vec2 o=vec2(hash(n+g),hash(n+g+vec2(31.3,17.7)));
    vec2 r=g+o-f;float d=dot(r,r);
    float sel=step(d,md);md2=mix(md2,md,sel);md=mix(md,d,sel);mg=mix(mg,n+g,sel);
  }
  return vec3(sqrt(md),sqrt(md2)-sqrt(md),hash(mg));
}
float destructionAt(vec3 p){
  // Expanding wavefront model: destruction ring propagates outward
  float waveR=uImpactRing*0.5;           // wavefront radius (0→40 at peak)
  float cd=length(p.xz-uMeteorImpact);
  // Peak at wavefront edge, fading behind
  float waveDist=abs(cd-waveR);
  float waveW=max(waveR*0.35,2.0);       // wave width scales with radius
  float invW=1.0/(waveW+0.001);
  float wave=SAT(1.0-waveDist*invW);
  // Also radial core destruction (near impact = always destroyed)
  float coreR=max(uImpactRing*0.12,1.0);
  float core=SAT(1.0-cd*(1.0/(coreR+0.001)));
  return max(wave,core)*uShatter;
}
float sdDestruction(vec3 p,float orig,float destr){
  float gate=step(0.005,destr);
  vec3 v=voronoi2(p.xz*5.0);
  float crack=v.y;
  crack=smoothstep(0.0,0.05*(1.0-destr*0.95),crack);
  float cracked=orig+(1.0-crack)*0.1*destr;
  float cellHash=v.z;
  float remove=step(cellHash,destr*0.7)*gate;
  cracked=mix(cracked,1e5,remove);
  return mix(orig,cracked,gate);
}
float sdDebris(vec3 p,float t,vec2 center){
  float gate=step(0.15,t);
  vec2 cellId=floor(p.xz*3.0);
  float h=hash(cellId+center*7.13);
  float fallGate=step(h,t*1.2)*gate;
  float fallTime=max(t-h,0.0);
  vec3 q=p;
  q.y+=4.9*fallTime*fallTime;
  q.xz+=(vec2(hash(cellId+vec2(5.3,1.7)),hash(cellId+vec2(9.1,3.2)))-0.5)*fallTime*0.5;
  float ca=cos(fallTime*(h*5.0+1.0));float sa=sin(fallTime*(h*5.0+1.0));
  q.xy=vec2(q.x*ca-q.y*sa,q.x*sa+q.y*ca);
  float sz=0.08+h*0.12;
  float db=sdBox(q-vec3(0,sz,0),vec3(sz,sz*0.5,sz*0.7));
  return mix(1e5,db,fallGate);
}

// ═══ Scene ═══
vec2 map(vec3 p){
  float d=p.y;
  {float impG=step(0.01,uImpact);vec2 cp=p.xz-uMeteorImpact;float cd=length(cp);float cR=max(uImpactRing*0.06,0.3);d-=smoothstep(cR,cR*0.15,cd)*cR*0.4*uImpact*impG;}
  float id=0.0;

  float dcz=length(p.xz)-16.0;
  if(dcz<d){
    // Energy Orb — Lobby
    vec3 ecp=p-vec3(0,5.2,0);
    float eOrb=sdSphere(ecp,2.2)+disp(ecp*2.0+uTime*0.3)*0.08;
    {float s=step(eOrb,d);d=mix(d,eOrb,s);id=mix(id,1.0,s);}
    vec3 rp1=ecp;rp1.xz=rot(uTime*0.12)*rp1.xz;rp1.xy=rot(0.35)*rp1.xy;
    float ring1=sdTorus(rp1,vec2(3.8,0.06));
    {float s=step(ring1,d);d=mix(d,ring1,s);id=mix(id,17.0,s);}
    vec3 rp2=ecp;rp2.xz=rot(-uTime*0.08)*rp2.xz;rp2.yz=rot(-0.25)*rp2.yz;
    float ring2=sdTorus(rp2,vec2(3.2,0.035));
    {float s=step(ring2,d);d=mix(d,ring2,s);id=mix(id,17.0,s);}
    if(uShatter>0.005){
    float lDst=destructionAt(p);
    for(int i=0;i<4;i++){
      float ang=float(i)*1.5707963;
      vec3 pp=p-vec3(cos(ang)*5.5,3.5,sin(ang)*5.5);pp.xz=rot(pp.y*0.28)*pp.xz;
      float pil=sdRoundBox(pp,vec3(0.13,3.5,0.13),0.008);vec3 pp2=pp;pp2.xz=rot(0.7854)*pp2.xz;
      pil=min(pil,sdRoundBox(pp2,vec3(0.13,3.5,0.13),0.008));
      pil=min(pil,sdCylinder(p-vec3(cos(ang)*5.5,0.12,sin(ang)*5.5),0.12,0.35));
      pil=min(pil,sdCylinder(p-vec3(cos(ang)*5.5,6.88,sin(ang)*5.5),0.12,0.35));
      pil=sdDestruction(p,pil,lDst);
      {float s=step(pil,d);d=mix(d,pil,s);id=mix(id,2.0,s);}
    }
    float cbase=sdRoundBox(p-vec3(0,0.22,0),vec3(7.5,0.22,7.5),0.1);
    cbase=sdDestruction(p,cbase,lDst);
    {float csgR=max(uImpactRing*0.04,0.2)*uShatter;float csgD=sdSphere(p-vec3(uMeteorImpact.x,0.0,uMeteorImpact.y),csgR);cbase=max(cbase,-csgD);}
    {float s=step(cbase,d);d=mix(d,cbase,s);id=mix(id,9.0,s);}
    vec3 a1=p-vec3(0,7.2,0);float arch=sdTorus(a1,vec2(6.2,0.055));
    vec3 a2=p-vec3(0,6.2,0);a2.xz=rot(0.7854)*a2.xz;a2.xy=rot(0.35)*a2.xy;arch=min(arch,sdTorus(a2,vec2(5.7,0.04)));
    vec3 a3=p-vec3(0,5.2,0);a3.xz=rot(1.5708)*a3.xz;a3.yz=rot(-0.25)*a3.yz;arch=min(arch,sdTorus(a3,vec2(5.2,0.035)));
    arch=sdDestruction(p,arch,lDst*0.7);
    {float s=step(arch,d);d=mix(d,arch,s);id=mix(id,10.0,s);}
    }else{
    for(int i=0;i<4;i++){
      float ang=float(i)*1.5707963;
      vec3 pp=p-vec3(cos(ang)*5.5,3.5,sin(ang)*5.5);pp.xz=rot(pp.y*0.28)*pp.xz;
      float pil=sdRoundBox(pp,vec3(0.13,3.5,0.13),0.008);vec3 pp2=pp;pp2.xz=rot(0.7854)*pp2.xz;
      pil=min(pil,sdRoundBox(pp2,vec3(0.13,3.5,0.13),0.008));
      pil=min(pil,sdCylinder(p-vec3(cos(ang)*5.5,0.12,sin(ang)*5.5),0.12,0.35));
      pil=min(pil,sdCylinder(p-vec3(cos(ang)*5.5,6.88,sin(ang)*5.5),0.12,0.35));
      {float s=step(pil,d);d=mix(d,pil,s);id=mix(id,2.0,s);}
    }
    float cbase=sdRoundBox(p-vec3(0,0.22,0),vec3(7.5,0.22,7.5),0.1);
    {float s=step(cbase,d);d=mix(d,cbase,s);id=mix(id,9.0,s);}
    vec3 a1=p-vec3(0,7.2,0);float arch=sdTorus(a1,vec2(6.2,0.055));
    vec3 a2=p-vec3(0,6.2,0);a2.xz=rot(0.7854)*a2.xz;a2.xy=rot(0.35)*a2.xy;arch=min(arch,sdTorus(a2,vec2(5.7,0.04)));
    vec3 a3=p-vec3(0,5.2,0);a3.xz=rot(1.5708)*a3.xz;a3.yz=rot(-0.25)*a3.yz;arch=min(arch,sdTorus(a3,vec2(5.2,0.035)));
    {float s=step(arch,d);d=mix(d,arch,s);id=mix(id,10.0,s);}
    }
  }

  float dnz=abs(p.z+35.0)-18.0;
  if(dnz<d){
    if(uShatter>0.005){
    float sDst=destructionAt(p);
    for(int i=0;i<4;i++){float x=float(i)*4.0-6.0;float h=5.2+sin(float(i)*1.5)*0.4;
      float svc=sdRoundBox(p-vec3(x,h*0.5,-35.0),vec3(1.55,h*0.5,0.28),0.12);svc=sdDestruction(p,svc,sDst);{float s=step(svc,d);d=mix(d,svc,s);id=mix(id,3.0,s);}}
    float sbase=sdRoundBox(p-vec3(0,0.14,-35.0),vec3(11.5,0.14,4.5),0.08);sbase=sdDestruction(p,sbase,sDst);
    {float csgR=max(uImpactRing*0.04,0.2)*uShatter;float csgD=sdSphere(p-vec3(uMeteorImpact.x,0.0,uMeteorImpact.y),csgR);sbase=max(sbase,-csgD);}
    {float s=step(sbase,d);d=mix(d,sbase,s);id=mix(id,9.0,s);}
    }else{
    for(int i=0;i<4;i++){float x=float(i)*4.0-6.0;float h=5.2+sin(float(i)*1.5)*0.4;
      float svc=sdRoundBox(p-vec3(x,h*0.5,-35.0),vec3(1.55,h*0.5,0.28),0.12);{float s=step(svc,d);d=mix(d,svc,s);id=mix(id,3.0,s);}}
    float sbase=sdRoundBox(p-vec3(0,0.14,-35.0),vec3(11.5,0.14,4.5),0.08);{float s=step(sbase,d);d=mix(d,sbase,s);id=mix(id,9.0,s);}
    }
    for(int i=0;i<4;i++){float x=float(i)*4.0-6.0;
      float beam=sdCylinder(p-vec3(x,0.0,-34.3),10.0,0.018);{float s=step(beam,d);d=mix(d,beam,s);id=mix(id,11.0,s);}}
    vec3 sep=p-vec3(0,6.5,-35);
    float seOrb=sdSphere(sep,1.8)+disp(sep*2.2+uTime*0.35)*0.06;
    {float s=step(seOrb,d);d=mix(d,seOrb,s);id=mix(id,1.0,s);}
    vec3 srp=sep;srp.xz=rot(uTime*0.15)*srp.xz;srp.xy=rot(0.3)*srp.xy;
    float sring=sdTorus(srp,vec2(3.0,0.05));
    {float s=step(sring,d);d=mix(d,sring,s);id=mix(id,17.0,s);}
  }

  float dez=abs(p.x-35.0)-15.0;
  if(dez<d){
    float res=sdRoundBox(p-vec3(35.0,4.8,0),vec3(0.35,4.8,8.5),0.15);
    float gy=sdGyroid(p-vec3(35.0,4.8,0),1.3,0.12);
    float gyWall=max(res,-gy);
    float inner=max(sdRoundBox(p-vec3(35.0,4.8,0),vec3(0.18,4.3,8.0),0.0),gy);
    float rbase=sdRoundBox(p-vec3(35.0,0.14,0),vec3(2.8,0.14,10.5),0.08);
    float rf=sdRoundBox(p-vec3(34.55,4.8,0),vec3(0.06,5.1,8.8),0.025);
    rf=max(rf,-sdRoundBox(p-vec3(34.55,4.8,0),vec3(1.0,4.5,8.0),0.0));
    if(uShatter>0.005){
    float rDst=destructionAt(p);
    gyWall=sdDestruction(p,gyWall,rDst);inner=sdDestruction(p,inner,rDst);
    rbase=sdDestruction(p,rbase,rDst);rf=sdDestruction(p,rf,rDst);
    {float csgR=max(uImpactRing*0.04,0.2)*uShatter;float csgD=sdSphere(p-vec3(uMeteorImpact.x,0.0,uMeteorImpact.y),csgR);rbase=max(rbase,-csgD);}
    }
    {float s=step(gyWall,d);d=mix(d,gyWall,s);id=mix(id,4.0,s);}
    {float s=step(inner,d);d=mix(d,inner,s);id=mix(id,12.0,s);}
    vec3 rep=p-vec3(35,5.5,0);
    float reOrb=sdSphere(rep,1.6)+disp(rep*2.4+uTime*0.4)*0.05;
    {float s=step(reOrb,d);d=mix(d,reOrb,s);id=mix(id,1.0,s);}
    vec3 rrp=rep;rrp.xz=rot(uTime*0.14)*rrp.xz;rrp.yz=rot(0.28)*rrp.yz;
    float rring=sdTorus(rrp,vec2(2.8,0.045));
    {float s=step(rring,d);d=mix(d,rring,s);id=mix(id,17.0,s);}
    {float s=step(rbase,d);d=mix(d,rbase,s);id=mix(id,9.0,s);}
    {float s=step(rf,d);d=mix(d,rf,s);id=mix(id,10.0,s);}
  }

  float dsz=abs(p.z-35.0)-15.0;
  if(dsz<d){
    if(uShatter>0.005){
    float tDst=destructionAt(p);
    for(int i=0;i<4;i++){float x=float(i)*4.0-6.0;
      float st=sdRoundBox(p-vec3(x,1.6,35.0),vec3(1.05,1.6,1.05),0.1);st=sdDestruction(p,st,tDst);{float s=step(st,d);d=mix(d,st,s);id=mix(id,5.0,s);}}
    float stbase=sdRoundBox(p-vec3(0,0.14,35.0),vec3(11.5,0.14,4.5),0.08);stbase=sdDestruction(p,stbase,tDst);
    {float csgR=max(uImpactRing*0.04,0.2)*uShatter;float csgD=sdSphere(p-vec3(uMeteorImpact.x,0.0,uMeteorImpact.y),csgR);stbase=max(stbase,-csgD);}
    {float s=step(stbase,d);d=mix(d,stbase,s);id=mix(id,9.0,s);}
    }else{
    for(int i=0;i<4;i++){float x=float(i)*4.0-6.0;
      float st=sdRoundBox(p-vec3(x,1.6,35.0),vec3(1.05,1.6,1.05),0.1);{float s=step(st,d);d=mix(d,st,s);id=mix(id,5.0,s);}}
    float stbase=sdRoundBox(p-vec3(0,0.14,35.0),vec3(11.5,0.14,4.5),0.08);{float s=step(stbase,d);d=mix(d,stbase,s);id=mix(id,9.0,s);}
    }
    for(int i=0;i<4;i++){float x=float(i)*4.0-6.0;float phase=uTime+float(i)*1.3;
      vec3 gp=p-vec3(x,4.3+sin(phase)*0.55,35.0);gp.xz=rot(uTime*(0.45+float(i)*0.12))*gp.xz;gp.xy=rot(uTime*0.28)*gp.xy;
      vec3 gp2=gp;gp2.y*=0.6;float gem=sdOctahedron(gp2,0.6);gem=max(gem,sdBox(gp,vec3(0.48,0.38,0.48)));
      {float s=step(gem,d);d=mix(d,gem,s);id=mix(id,6.0,s);}}
    vec3 stp2=p-vec3(0,5.0,35);
    float stOrb=sdSphere(stp2,1.6)+disp(stp2*2.4+uTime*0.32)*0.05;
    {float s=step(stOrb,d);d=mix(d,stOrb,s);id=mix(id,1.0,s);}
    vec3 strp=stp2;strp.xz=rot(-uTime*0.13)*strp.xz;strp.xy=rot(-0.3)*strp.xy;
    float stRing=sdTorus(strp,vec2(2.8,0.045));
    {float s=step(stRing,d);d=mix(d,stRing,s);id=mix(id,17.0,s);}
  }

  float dwz=abs(p.x+35.0)-12.0;
  if(dwz<d){
    vec3 cep=p-vec3(-35,5.2,0);
    float ceOrb=sdSphere(cep,1.8)+disp(cep*2.2+uTime*0.38)*0.06;
    {float s=step(ceOrb,d);d=mix(d,ceOrb,s);id=mix(id,1.0,s);}
    vec3 crp=cep;crp.xz=rot(uTime*0.11)*crp.xz;crp.xy=rot(0.32)*crp.xy;
    float cring=sdTorus(crp,vec2(3.2,0.055));
    {float s=step(cring,d);d=mix(d,cring,s);id=mix(id,17.0,s);}
    vec3 crp2=cep;crp2.xz=rot(-uTime*0.09)*crp2.xz;crp2.yz=rot(-0.2)*crp2.yz;
    float cring2=sdTorus(crp2,vec2(2.6,0.035));
    {float s=step(cring2,d);d=mix(d,cring2,s);id=mix(id,17.0,s);}
    float pbase=sdRoundBox(p-vec3(-35.0,0.14,0),vec3(6.5,0.14,6.5),0.08);
    if(uShatter>0.005){
    float cDst=destructionAt(p);
    pbase=sdDestruction(p,pbase,cDst);
    {float csgR=max(uImpactRing*0.04,0.2)*uShatter;float csgD=sdSphere(p-vec3(uMeteorImpact.x,0.0,uMeteorImpact.y),csgR);pbase=max(pbase,-csgD);}
    {float s=step(pbase,d);d=mix(d,pbase,s);id=mix(id,9.0,s);}
    for(int i=0;i<2;i++){float zz=float(i)*10.0-5.0;vec3 pp=p-vec3(-35.0,3.5,zz);pp.xz=rot(pp.y*0.22)*pp.xz;
      float pil=sdRoundBox(pp,vec3(0.15,3.5,0.15),0.008);vec3 pp2=pp;pp2.xz=rot(0.7854)*pp2.xz;
      pil=min(pil,sdRoundBox(pp2,vec3(0.15,3.5,0.15),0.008));pil=sdDestruction(p,pil,cDst);{float s=step(pil,d);d=mix(d,pil,s);id=mix(id,10.0,s);}}
    }else{
    {float s=step(pbase,d);d=mix(d,pbase,s);id=mix(id,9.0,s);}
    for(int i=0;i<2;i++){float zz=float(i)*10.0-5.0;vec3 pp=p-vec3(-35.0,3.5,zz);pp.xz=rot(pp.y*0.22)*pp.xz;
      float pil=sdRoundBox(pp,vec3(0.15,3.5,0.15),0.008);vec3 pp2=pp;pp2.xz=rot(0.7854)*pp2.xz;
      pil=min(pil,sdRoundBox(pp2,vec3(0.15,3.5,0.15),0.008));{float s=step(pil,d);d=mix(d,pil,s);id=mix(id,10.0,s);}}
    }
  }

  float orb=sdSphere(p-vec3(sin(uTime*0.4)*20.0,3.8+sin(uTime*0.7),cos(uTime*0.35)*20.0),0.38);
  orb=min(orb,sdSphere(p-vec3(cos(uTime*0.3)*24.0,6.0+cos(uTime*0.5),sin(uTime*0.5)*24.0),0.3));
  orb=min(orb,sdSphere(p-vec3(sin(uTime*0.6)*15.0,3.0+sin(uTime*0.8)*2.0,cos(uTime*0.25)*18.0),0.24));
  {float s=step(orb,d);d=mix(d,orb,s);id=mix(id,8.0,s);}

  // Glass dome
  float gls=sdSphere(p-vec3(0,12.5,0),3.0);gls=max(gls,-sdSphere(p-vec3(0,12.5,0),2.75));gls=max(gls,-(p.y-12.5));
  if(uShatter>0.005){float dDst=destructionAt(p);gls=sdDestruction(p+vec3(0,5.0,0),gls,dDst*0.6);}
  {float s=step(gls,d);d=mix(d,gls,s);id=mix(id,16.0,s);}

  // Meteor + fire trail (branchless)
  {float metG=step(0.5,uMeteorActive);
    vec3 mp=p-vec3(uMeteorImpact.x,uMeteorY,uMeteorImpact.y);
    float mD=sdSphere(mp,2.8)+disp(mp*0.8+uTime*0.5)*0.2;
    mD=mix(1e5,mD,metG);float mSel=step(mD,d);d=mix(d,mD,mSel);id=mix(id,14.0,mSel);
    // Thin laser tail — branchless gate
    float tailG=step(1.5,mp.y)*metG;
    float ty=max(mp.y-1.5,0.0)*0.022;float tR=0.1+ty*ty*0.55;
    float tail=length(mp.xz)-tR+vnoise3(mp*vec3(3.5,0.15,3.5)+vec3(0,uTime*6.0,0))*0.04;
    tail=mix(1e5,tail,tailG);float tSel=step(tail,d);d=mix(d,tail,tSel);id=mix(id,15.0,tSel);
  }

  // Structural debris (Law D-2) — uniform guard
  if(uShatter>0.1){
    float deb=sdDebris(p,uShatter,uMeteorImpact);
    float debSel=step(deb,d);d=mix(d,deb,debSel);id=mix(id,18.0,debSel);
  }

  return vec2(d,id);
}

// ═══ Normal / AO / Shadow ═══
vec3 calcN(vec3 p,float dist){float e=max(0.0002,dist*0.0003);vec2 k=vec2(e,-e);return normalize(k.xyy*map(p+k.xyy).x+k.yyx*map(p+k.yyx).x+k.yxy*map(p+k.yxy).x+k.xxx*map(p+k.xxx).x);}
float ao(vec3 p,vec3 n){float o=0.0,w=1.0;for(int i=0;i<6;i++){float h=0.008+0.12*float(i);o+=(h-map(p+n*h).x)*w;w*=0.58;}return SAT(1.0-4.0*o);}
// Shadow Proxy: 2 SDF evaluations (map() 20→2, Reality Law compliant)
float shadowProxy(vec3 p,vec3 n,vec3 lDir){float h1=0.1,h2=0.4;float d1=map(p+lDir*h1).x;float d2=map(p+lDir*h2).x;float occ=SAT((d1/h1+d2/h2)*0.5);float NdL=max(dot(n,lDir),0.0);return occ*NdL;}

// ═══ Rain Occlusion (upward SDF trace) ═══
float rainOcc(vec3 p){
  float t=0.3;
  for(int i=0;i<3;i++){float h=map(p+vec3(0,t,0)).x;if(h<0.08)return 0.0;t+=max(h,0.5);}
  return 1.0;
}

// ═══ PBR ═══
float D_GGX(float NdH,float r){float a=r*r;float a2=a*a;float d=NdH*NdH*(a2-1.0)+1.0;float id2=1.0/(d*d+0.0001);return a2*0.31831*id2;}
float G_SchlickGGX(float NdV,float r){float k=(r+1.0)*(r+1.0)*0.125;return NdV*(1.0/(NdV*(1.0-k)+k));}
float G_Smith(float NdV,float NdL,float r){return G_SchlickGGX(NdV,r)*G_SchlickGGX(NdL,r);}
vec3 F_Schlick(float c,vec3 F0){float t=SAT(1.0-c);float t2=t*t;return F0+(1.0-F0)*(t2*t2*t);}
vec3 pbrDirect(vec3 n,vec3 V,vec3 L,vec3 lc,Mat m,vec3 F0){float NdL=max(dot(n,L),0.0);float NdV=max(dot(n,V),0.001);vec3 H=normalize(L+V);float NdH=max(dot(n,H),0.0);float HdV=max(dot(H,V),0.0);float D=D_GGX(NdH,m.roughness);float G=G_Smith(NdV,NdL,m.roughness);vec3 F=F_Schlick(HdV,F0);float invDenom=1.0/(4.0*NdV*NdL+0.001);vec3 spec=D*G*F*invDenom;vec3 kD=(1.0-F)*(1.0-m.metallic);return(kD*m.albedo*0.31831+spec)*NdL*lc;}
vec3 pointLight(vec3 p,vec3 n,vec3 V,Mat m,vec3 F0,vec3 lP,vec3 lC,float rad){vec3 L=lP-p;float dist=length(L);float invDist=1.0/(dist+0.0001);float invRad=1.0/(rad+0.0001);L*=invDist;float at=SAT(1.0-dist*invRad);at*=at;float gate=step(dist,rad);float NdL=max(dot(n,L),0.0);vec3 H=normalize(L+V);float rr=m.roughness*m.roughness;float invRR=1.0/(max(rr,0.01));float sp=pow(max(dot(n,H),0.0),max(2.0*invRR,2.0));vec3 F=F_Schlick(max(dot(H,V),0.0),F0);return(m.albedo*(1.0-m.metallic)*0.31831+F*sp*0.3)*NdL*lC*at*gate;}

// ═══ Volumetric Scatter (analytic height-fog — zero loops, zero map() calls) ═══
vec3 volScatter(vec3 ro,vec3 rd,vec3 lDir,float maxD,float dayF,vec2 fc){
  float mu=dot(rd,lDir);float g=0.76,g2=g*g;
  float dSq=inversesqrt(max(1.0+g2-2.0*g*mu,0.0001));
  float phase=0.079577*(1.0-g2)*dSq*dSq*dSq;
  // Analytic height-fog integral (Beer-Lambert, no loops)
  float h0=max(ro.y,0.0);float hEnd=max(ro.y+rd.y*maxD,0.0);
  float avgH=(h0+hEnd)*0.5;
  float dens=exp(-avgH*0.3)*maxD*0.06;
  // Directional shadow approximation: sun angle occlusion
  float sunOcc=SAT(lDir.y*2.0+0.5);dens*=sunOcc;
  // Blue noise temporal dither
  float bn=fract(52.9829189*fract(dot(fc,vec2(0.06711056,0.00583715))));
  dens*=(0.9+fract(uTime*7.23+bn*0.5)*0.2);
  return vec3(phase*dens)*mix(vec3(0.08,0.1,0.18),vec3(1.0,0.95,0.8),dayF);
}

// ═══ Sky (Physical Rayleigh/Mie + Volumetric Clouds) ═══
vec3 skyColor(vec3 rd,vec3 sunDir,vec3 moonDir,float dayF){
  float y=rd.y;
  float mu=dot(rd,sunDir);
  float sunH=sunDir.y;
  float nightF=1.0-dayF;
  float goldenF=exp(-sunH*sunH*12.0)*smoothstep(-0.15,0.05,sunH);

  // ── Chapman function optical depth ──
  // Scale heights: Rayleigh H_R=8.0km (~normalized), Mie H_M=1.2km
  vec3 bR=vec3(5.8,13.5,33.1)*1e-3;
  float bM=0.021;
  float cosZ=max(y,0.0)+0.001;
  float sunCZ=max(sunH,0.0)+0.001;
  // Chapman approximation: Ch(x,chi) ~ sqrt(PI*x/2) * (1/cosZ) for cosZ>0
  // Simplified: am = 1/(cosZ + 0.15*cosZ^(3/5)) — Schaefer polynomial
  float cosZ35=pow(cosZ,0.6);
  float am=1.0/(cosZ+0.15*cosZ35);
  float sunCZ35=pow(sunCZ,0.6);
  float sunAm=1.0/(sunCZ+0.15*sunCZ35);
  // Dual-scale optical depth (Rayleigh deeper, Mie shallower)
  float densR=exp(-max(y,0.0)*3.0);    // H_R scale
  float densM=exp(-max(y,0.0)*1.2);    // H_M scale (lower = thicker near horizon)
  vec3 extR=exp(-bR*sunAm*1.5);
  float extM=exp(-bM*sunAm*0.8);

  // ── Rayleigh Scattering ──
  float phR=0.059683*(1.0+mu*mu);
  vec3 rayleigh=bR*phR*am*densR*extR;

  // ── Mie Scattering ──
  float g=0.76,g2=g*g;
  float denomMie=max(1.0+g2-2.0*g*mu,0.0001);
  float denomSqrt=inversesqrt(denomMie);
  float phM=0.079577*(1.0-g2)*denomSqrt*denomSqrt*denomSqrt;
  vec3 mie=vec3(bM*phM*(am*0.5)*densM)*extR*extM;

  // ── Ozone absorption (blue moment) ──
  // Ozone Chappuis band absorbs 500-700nm (green-red), leaving blue at twilight
  vec3 bO=vec3(0.065,0.19,0.005)*1e-2; // ozone cross-section (R,G,B)
  float ozoneAm=1.0/(max(sunH+0.1,0.001)+0.05); // deep airmass at twilight
  float ozoneF=smoothstep(-0.1,-0.02,sunH)*smoothstep(0.15,0.04,sunH); // twilight window
  vec3 ozoneExt=exp(-bO*ozoneAm*5.0)*ozoneF;

  // ── Combined atmosphere ──
  vec3 sunI=vec3(22.0,20.0,17.0)*smoothstep(-0.08,0.15,sunH);
  sunI*=mix(vec3(1),ozoneExt+vec3(0.3,0.2,0.8),ozoneF); // ozone absorption on sun path
  vec3 sky=(rayleigh+mie)*sunI;
  // Blue moment: residual ozone blue fill at civil twilight
  sky*=mix(vec3(1),vec3(0.7,0.75,1.3),ozoneF*0.4);
  sky+=vec3(0.001,0.004,0.025)*ozoneF*smoothstep(-0.1,0.3,y); // deep blue fill
  sky+=vec3(0.0,0.003,0.015)*max(y,0.0)*dayF;
  sky+=vec3(0.003,0.004,0.005)*smoothstep(-0.3,0.2,y)*dayF;

  // ── Sun disc (limb darkening) ──
  float sunAng=acos(clamp(mu,-1.0,1.0));
  float sunR=0.0046;
  float sunDisc=smoothstep(sunR*1.3,sunR*0.4,sunAng);
  float limbT=min(sunAng/sunR,1.0);
  float limb=1.0-0.6*(1.0-sqrt(max(1.0-limbT*limbT,0.0)));
  sky+=vec3(12.0,10.0,7.0)*sunDisc*max(limb,0.0)*smoothstep(-0.05,0.05,sunH);
  sky+=vec3(0.4,0.3,0.15)*pow(max(mu,0.0),128.0)*0.6*smoothstep(-0.02,0.1,sunH);

  // ── Golden hour bloom ──
  sky+=vec3(0.35,0.12,0.03)*goldenF*exp(-abs(y)*3.0)*0.5;
  sky+=vec3(0.6,0.25,0.08)*goldenF*pow(max(mu,0.0),4.0)*0.2;

  // ── Moon ──
  float moonDot=max(dot(rd,moonDir),0.0);
  float moonAng=acos(clamp(dot(rd,moonDir),-1.0,1.0));
  float moonDisc=smoothstep(0.009,0.003,moonAng);
  sky+=vec3(0.5,0.55,0.65)*moonDisc*nightF*1.5;
  sky+=vec3(0.1,0.12,0.18)*pow(moonDot,24.0)*0.2*nightF;

  // ── Stars (magnitude-based, spectral color) ──
  vec3 sid=floor(rd*420.0);
  float ss=hash3(sid);
  float mag=pow(ss,0.25);
  float starB=smoothstep(0.88,1.0,mag);
  starB*=0.5+0.5*sin(uTime*(hash3(sid+200.0)*3.5+0.5));
  float bv=hash3(sid+300.0);
  vec3 starC=mix(
    mix(vec3(0.6,0.7,1.0),vec3(1.0,0.97,0.93),smoothstep(0.0,0.4,bv)),
    mix(vec3(1.0,0.85,0.65),vec3(1.0,0.6,0.35),smoothstep(0.5,1.0,bv)),
    smoothstep(0.35,0.55,bv));
  sky+=starC*starB*0.5*nightF*smoothstep(0.0,0.08,y);

  // ── Milky Way ──
  float mwDot=abs(dot(rd,normalize(vec3(0.3,0.7,0.15))));
  float mwAng=acos(clamp(mwDot,0.0,1.0));
  float mwBand=exp(-(mwAng-0.2)*(mwAng-0.2)*6.0);
  sky+=vec3(0.045,0.03,0.06)*mwBand*fbm(rd.xz*3.5+rd.y*2.0)*nightF*smoothstep(0.05,0.35,y);

  // ── Nebula ──
  sky+=vec3(0.07,0.012,0.11)*fbm(rd.xz*2.5+rd.y*1.5)*0.13*(1.0-abs(y))*nightF;
  sky+=vec3(0.012,0.04,0.09)*fbm(rd.xz*3.5-rd.y*2.0+100.0)*0.09*(1.0-abs(y))*nightF;

  // ── Aurora ──
  float aurora=smoothstep(0.2,0.55,y)*smoothstep(0.8,0.45,y);
  float aN=fbm(vec2(rd.x*4.0+uTime*0.08,rd.z*2.5+uTime*0.04));
  sky+=vec3(0.0,0.18,0.08)*aurora*aN*0.2*nightF;
  sky+=vec3(0.06,0.0,0.1)*aurora*(1.0-aN)*0.08*nightF;

  // ── Volumetric Clouds (dual layer) ──
  if(y>0.008){
    float invY=1.0/y;
    // Cumulus
    vec2 cUV=rd.xz*invY*0.12+uTime*vec2(0.003,0.001);
    float cn=fbm(cUV*4.0);
    float cn2=vnoise(cUV*16.0+30.0);
    float cover=0.08+uWxFog*0.35+uWxRain*0.4;
    float cD=smoothstep(0.4-cover,0.7,cn+cn2*0.15)*smoothstep(0.008,0.12,y);
    float cLit=smoothstep(0.35,0.75,cn)*0.6+0.4;
    cLit*=max(sunH+0.2,0.08);
    vec3 cBr=mix(vec3(0.04,0.045,0.06),vec3(1.0,0.95,0.85),dayF)*cLit;
    vec3 cDk=mix(vec3(0.012,0.015,0.025),vec3(0.3,0.3,0.35),dayF);
    cDk=mix(cDk,cDk*0.25,uWxRain*0.7);
    cBr+=vec3(1.0,0.45,0.15)*goldenF*0.8;
    cDk+=vec3(0.5,0.2,0.08)*goldenF*0.3;
    float edge=smoothstep(0.55,0.45,cn)*smoothstep(0.3,0.4,cn);
    vec3 cCol=mix(cDk,cBr,cLit)+vec3(0.7,0.65,0.55)*edge*dayF*0.25;
    sky=mix(sky,cCol,SAT(cD));
    // Cirrus
    vec2 ciUV=rd.xz*invY*0.05+uTime*vec2(0.005,0.002);
    float ci=fbm(ciUV*10.0);
    float ciD=smoothstep(0.52,0.78,ci)*0.3*smoothstep(0.1,0.35,y);
    vec3 ciC=mix(vec3(0.025,0.03,0.04),vec3(0.55,0.55,0.6),dayF)+vec3(0.4,0.2,0.08)*goldenF*0.4;
    sky=mix(sky,ciC,SAT(ciD));
  }

  // ── Fog ──
  vec3 fogT=mix(vec3(0.02,0.025,0.04),vec3(0.3,0.33,0.38),dayF);
  sky=mix(sky,fogT,uWxFog*0.55);
  return max(sky,vec3(0));
}

// ═══ Main ═══
void main(){
  vec2 uv=(gl_FragCoord.xy-0.5*uRes)/uRes.y;
  vec3 ro=uCamPos;
  vec2 sUV=uv+uShake;
  if(uImpact>0.1){sUV+=vec2(sin(uv.y*35.0+uTime*8.0),cos(uv.x*28.0+uTime*6.0))*uImpact*0.012;}
  vec3 rd=normalize(uCamFwd+sUV.x*uCamRight+sUV.y*uCamUp);

  // ── Time of Day ──
  float sunAngle=uDayPhase*TAU;
  float sunH=sin(sunAngle);
  vec3 sunDir=normalize(vec3(cos(sunAngle)*0.8,sunH,0.35));
  vec3 moonDir=normalize(vec3(-cos(sunAngle)*0.6,max(-sunH*0.8,0.15),-0.3));
  float dayF=smoothstep(-0.1,0.3,sunH);
  float goldenF=exp(-sunH*sunH*12.0)*smoothstep(-0.15,0.05,sunH);

  vec3 sky=skyColor(rd,sunDir,moonDir,dayF);

  // Raymarch + analytic bloom accumulation
  float t=0.0;vec2 hit;vec3 bloomAcc=vec3(0);
  for(int i=0;i<96;i++){
    hit=map(ro+rd*t);
    // Analytic bloom: branchless accumulation via step masks
    float bm1=step(0.5,hit.y)*step(hit.y,1.5);
    float bm2=step(16.5,hit.y)*step(hit.y,17.5);
    float bm3=step(13.5,hit.y)*step(hit.y,15.5);
    bloomAcc+=bm1*aBloom(hit.x,vec3(0.3,0.5,1.0),0.012,8.0)+bm2*aBloom(hit.x,vec3(0.4,0.6,1.2),0.008,10.0)+bm3*aBloom(hit.x,blackbody(6000.0),0.015,6.0);
    if(hit.x<0.0004||t>uMaxDist)break;t+=hit.x;
  }

  vec3 col=sky+bloomAcc;
  float rocc=1.0;

  if(t<uMaxDist){
    vec3 p=ro+rd*t;
    vec3 n=calcN(p,t);
    vec3 V=-rd;

    // Floor bump
    if(hit.y<0.5){
      vec2 e=vec2(0.025,0);
      float nx=vnoise3(vec3(p.x+e.x,p.y,p.z)*4.0)-vnoise3(vec3(p.x-e.x,p.y,p.z)*4.0);
      float nz=vnoise3(vec3(p.x,p.y,p.z+e.x)*4.0)-vnoise3(vec3(p.x,p.y,p.z-e.x)*4.0);
      n=normalize(n+vec3(nx,0,nz)*0.6);
    }
    Mat mat=getMat(hit.y,p);
    rocc=1.0;if(uWxRain>0.01)rocc=rainOcc(p);
    // Law T: rain occlusion → restore floor roughness under roofs
    if(hit.y<0.5)mat.roughness=mix(mat.roughness,0.18,1.0-rocc);
    vec3 F0=mix(vec3(0.04),mat.albedo,mat.metallic);

    // ── Dynamic Lighting ──
    // Key light = sun during day, moon at night
    vec3 keyDir=mix(moonDir,sunDir,dayF);
    vec3 nightKey=vec3(0.06,0.08,0.18);
    vec3 dayKey=vec3(1.5,1.35,1.1);
    vec3 goldenKey=vec3(1.5,0.6,0.25);
    vec3 keyCol=mix(nightKey,dayKey,dayF);
    keyCol=mix(keyCol,goldenKey,goldenF*0.7);
    // Lightning boost
    keyCol+=vec3(2.0,2.2,2.8)*uLightning;

    float keyShadow=shadowProxy(p+n*0.015,n,keyDir);

    vec3 fillDir=normalize(vec3(-0.35,0.35,-0.6));
    vec3 fillCol=mix(vec3(0.03,0.04,0.08),vec3(0.18,0.25,0.45),dayF);

    vec3 rimDir=normalize(vec3(0.0,0.25,-0.9));
    vec3 rimCol=mix(vec3(0.04,0.05,0.1),vec3(0.25,0.35,0.5),dayF);

    float occ=ao(p,n);

    vec3 Lo=pbrDirect(n,V,keyDir,keyCol,mat,F0)*keyShadow;
    Lo+=pbrDirect(n,V,fillDir,fillCol,mat,F0);
    Lo+=pbrDirect(n,V,rimDir,rimCol,mat,F0);

    // Point lights
    Lo+=pointLight(p,n,V,mat,F0,vec3(0,7,0),vec3(0.5,0.4,0.7),20.0);
    Lo+=pointLight(p,n,V,mat,F0,vec3(0,6,-35),vec3(0.15,0.35,0.8),22.0);
    Lo+=pointLight(p,n,V,mat,F0,vec3(35,6,0),vec3(0.0,0.5,0.7),22.0);
    Lo+=pointLight(p,n,V,mat,F0,vec3(0,5,35),vec3(0.7,0.5,0.1),22.0);
    Lo+=pointLight(p,n,V,mat,F0,vec3(-35,6,0),vec3(0.6,0.1,0.4),22.0);

    // IBL-like ambient (6-direction irradiance probe)
    vec3 skyUp=mix(vec3(0.008,0.012,0.03),vec3(0.1,0.14,0.25),dayF);
    vec3 skyDn=mix(vec3(0.003,0.005,0.01),vec3(0.04,0.05,0.08),dayF);
    vec3 skyN=mix(vec3(0.004,0.006,0.015),vec3(0.06,0.08,0.14),dayF);
    vec3 skyS=skyN*0.8;
    vec3 irrDir=n*0.5+0.5;
    vec3 irr=mix(skyDn,skyUp,irrDir.y);
    irr+=mix(skyS,skyN,irrDir.z)*0.3;
    irr+=vec3(0.002,0.008,0.016)*max(-n.y,0.0);
    vec3 ambient=mat.albedo*(1.0-mat.metallic)*irr*occ;
    // Environment BRDF (Karis analytic polynomial — no LUT needed)
    float NdV=max(dot(n,V),0.001);
    float fresT=1.0-NdV;float fresT2=fresT*fresT;float fres=fresT2*fresT2*fresT;
    float r=mat.roughness;float r2=r*r;float r3=r2*r;float r4=r3*r;
    // Karis split-sum: scale & bias as f(NdV, roughness)
    float ebScale=1.0-max(r-0.04,0.0)*fres-r4*(1.0-NdV);
    ebScale=SAT(ebScale+(1.0-ebScale)*fres);
    float ebBias=fres*SAT(1.0-r2)+r4*0.04;
    vec2 envBRDF=vec2(ebScale,ebBias);
    vec3 specEnv=F0*envBRDF.x+(1.0-F0)*envBRDF.y;
    // Reflection irradiance (6-dir probe blend)
    vec3 reflDir=reflect(-V,n);
    float reflY=reflDir.y*0.5+0.5;
    vec3 reflIrr=mix(skyDn,skyUp,reflY)+mix(skyS,skyN,reflDir.z*0.5+0.5)*0.25;
    reflIrr=mix(reflIrr,irr*0.6,r);
    ambient+=specEnv*reflIrr*occ;
    // Multi-scatter GGX energy compensation (Turquin integral approx)
    float Ems=SAT(1.0-(envBRDF.x+envBRDF.y));
    vec3 Favg=F0+(1.0-F0)*0.047619;
    vec3 invMsDenom=1.0/(1.0-Favg*Ems+0.0001);vec3 msEnergy=Favg*Ems*invMsDenom;
    ambient+=msEnergy*irr*occ*0.25;
    vec3 rim=specEnv*fres*0.2;

    // SSS
    vec3 sssC=vec3(0);
    if(mat.sss>0.01){
      float bl=SAT(dot(n,-keyDir))*0.5+0.5;
      float ts=SAT(map(p+keyDir*0.3).x*5.0);
      sssC=mat.albedo*keyCol*bl*ts*mat.sss*0.12;
    }

    // Emission (brighter at night)
    float emBoost=mix(1.3,0.5,dayF);
    // Energy orb enhanced fresnel glow
    if(hit.y>0.5&&hit.y<1.5){rim+=mat.emission*fres*0.6;}
    if(hit.y>16.5&&hit.y<17.5){rim+=mat.emission*fres*0.4;}
    col=Lo*occ+ambient+mat.emission*emBoost+rim+sssC;

    // Floor SSR (Screen-Space Reflection)
    if(hit.y<0.5){
      vec3 reflDir=reflect(rd,n);
      float rt=0.0;vec2 rh;
      for(int i=0;i<32;i++){rh=map(p+reflDir*rt);if(rh.x<0.001||rt>45.0)break;rt+=rh.x*0.95;}
      vec3 reflCol=skyColor(reflDir,sunDir,moonDir,dayF);
      if(rt<45.0){
        vec3 rp=p+reflDir*rt;vec3 rn=calcN(rp,t+rt);Mat rm=getMat(rh.y,rp);
        float rNdL=max(dot(rn,keyDir),0.0);
        reflCol=rm.albedo*rNdL*keyCol*0.5+rm.emission*emBoost*0.8;
        reflCol+=rm.albedo*irr*0.15;
        reflCol*=exp(-rt*0.035);
      }
      float reflStr=envBRDF.x+envBRDF.y;
      float rainWet=uWxRain*0.35*rocc;
      reflStr=max(reflStr,rainWet);
      col=mix(col,reflCol,reflStr*(1.0-mat.roughness*0.8));
    }

    // ═══ Glass Shatter Cracks ═══
    if(uShatter>0.005){
      vec3 sp=p*0.5;vec3 cell=floor(sp);vec3 fr=fract(sp);
      vec3 df=min(fr,1.0-fr);float edist=min(df.x,min(df.y,df.z));
      float crack=smoothstep(0.12*uShatter,0.0,edist);
      vec3 cCol=mix(vec3(1.2,0.4,0.06),vec3(0.15,0.4,1.0),1.0-uEntropy);
      col+=cCol*crack*uShatter*2.5;
      col*=1.0-crack*0.55*uShatter;
      float cTint=hash3(cell)*0.2;col*=1.0+cTint*uShatter;
    }

    // ═══ Impact Shockwave Ring ═══
    if(uImpact>0.01&&uImpactRing>1.0){
      float rDist=abs(length(p.xz-uMeteorImpact)-uImpactRing);
      float ring=exp(-rDist*1.5)*uImpact;
      col+=mix(vec3(4.0,2.8,1.2),vec3(1.5,0.5,0.1),smoothstep(0.0,3.0,rDist))*ring*0.7;
      if(hit.y<0.5){col+=vec3(3.0,1.0,0.2)*exp(-rDist*0.6)*uImpact*0.4;}
    }
  }

  // ═══ Meteor Atmosphere ═══
  if(uMeteorActive>0.5){
    vec3 mwp=vec3(uMeteorImpact.x,max(uMeteorY,0.5),uMeteorImpact.y);
    vec3 toM=normalize(mwp-ro);float mDot=max(dot(rd,toM),0.0);
    // Intense core glow
    float mGlow=pow(mDot,32.0);col+=vec3(8.0,4.0,1.5)*mGlow*0.6;
    // Wide atmospheric scatter
    col+=vec3(1.5,0.4,0.08)*pow(mDot,6.0)*0.4;
    col+=vec3(0.6,0.15,0.03)*pow(mDot,2.0)*0.2;
    // Sky reddening + orange tint
    float skyRed=SAT(1.0-uMeteorY*0.005)*0.45;
    col=mix(col,col*vec3(1.5,0.55,0.35),skyRed);
    // Tail glow streak in sky
    float tailDot=max(dot(rd,vec3(0,1,0)),0.0)*max(dot(rd,toM),0.0);
    col+=vec3(3.0,1.5,0.5)*pow(tailDot,8.0)*0.3*(1.0-skyRed);
  }

  // ═══ Entropy Atmosphere Tint ═══
  if(uEntropy>0.3){
    float eFade=(uEntropy-0.3)*1.43;
    col=mix(col,col*vec3(1.15,0.85,0.7),eFade*0.12);
  }

  // ═══ Atmosphere ═══
  float weatherFogMul=1.0+uWxFog*6.0+uWxRain*2.0;
  float distFog=1.0-exp(-t*0.007*weatherFogMul);
  vec3 hitP=ro+rd*t;
  float heightFog=exp(-max(hitP.y,0.0)*0.12)*0.35*(1.0-exp(-t*0.015));
  float totalFog=SAT(distFog+heightFog);
  vec3 fogCol=mix(mix(vec3(0.005,0.008,0.025),vec3(0.2,0.22,0.28),dayF),sky*0.4,0.25);
  col=mix(col,fogCol,totalFog);

  // Volumetric light scatter (16-step with shadow rays per ALICE-SDF-PBR)
  float volDist=min(t,40.0);
  vec3 vol=volScatter(ro,rd,sunDir,volDist,dayF,gl_FragCoord.xy);
  col+=vol*(1.0-totalFog);
  // Analytic sun halo (cheap supplement)
  float godRayS=max(dot(rd,sunDir),0.0);
  float godHalo=pow(godRayS,48.0)*0.1+pow(godRayS,8.0)*0.02;
  vec3 godCol=mix(vec3(0.5,0.3,0.15),vec3(1.0,0.95,0.8),dayF);
  godCol=mix(godCol,vec3(0.8,0.35,0.1),goldenF*0.5);
  col+=godCol*godHalo*dayF*(1.0-totalFog);
  // Moon volumetric (analytic, no ray cost)
  float moonGR=pow(max(dot(rd,moonDir),0.0),32.0)*0.03*(1.0-dayF);
  col+=vec3(0.08,0.1,0.15)*moonGR*(1.0-totalFog);

  // ═══ HDR Effects (before tone mapping) ═══
  // Impact flash
  col+=vec3(5.0,3.5,2.0)*max(uImpact-0.6,0.0)*3.0;

  // Rain streaks — attenuate by depth (close surface = less air volume = less rain)
  // and by rocc (under roof = no rain)
  if(uWxRain>0.01){
    float rainDepth=smoothstep(3.0,35.0,t)*rocc;
    // Looking down at floor → rain streaks fade (rain hits surface, not air)
    rainDepth*=smoothstep(-0.5,-0.1,rd.y);
    vec2 ruv=gl_FragCoord.xy/uRes;
    vec2 rq=ruv*vec2(25.0,7.0);rq.y+=uTime*4.0;rq.x+=uTime*0.3;
    float r1=smoothstep(0.04,0.0,abs(fract(rq).x-0.5))*fract(rq).y*step(0.9,hash(floor(rq)));
    rq=ruv*vec2(50.0,12.0);rq.y+=uTime*5.5;rq.x-=uTime*0.15;
    float r2=smoothstep(0.025,0.0,abs(fract(rq).x-0.5))*fract(rq).y*step(0.92,hash(floor(rq)+300.0));
    col+=vec3(0.25,0.3,0.4)*(r1*0.3+r2*0.15)*uWxRain*rainDepth;
  }
  col+=vec3(0.5,0.55,0.7)*uLightning*0.6;

  // Lens flare (sun direction)
  float sunSZ=dot(sunDir,uCamFwd);
  if(sunSZ>0.05&&dayF>0.05){
    vec2 sunSS=vec2(dot(sunDir,uCamRight),dot(sunDir,uCamUp))/sunSZ;
    vec2 uvN=(gl_FragCoord.xy/uRes-0.5)*2.0;
    vec2 fD=uvN-sunSS;float fDist=length(fD);
    // Ghost rings
    float gh1=smoothstep(0.08,0.0,abs(fDist-0.4))*0.08;
    float gh2=smoothstep(0.06,0.0,abs(fDist-0.7))*0.05;
    float gh3=smoothstep(0.04,0.0,abs(fDist-1.1))*0.03;
    col+=mix(vec3(0.2,0.3,0.5),vec3(0.5,0.4,0.2),fDist)*(gh1+gh2+gh3)*dayF*smoothstep(0.0,0.2,sunH);
    // Anamorphic streak
    float streak=exp(-abs(uvN.y-sunSS.y)*10.0)*exp(-(uvN.x-sunSS.x)*(uvN.x-sunSS.x)*0.3);
    col+=vec3(0.12,0.16,0.25)*streak*0.12*dayF*smoothstep(0.0,0.15,sunH);
    // Starburst
    float ang=atan(fD.y,fD.x);
    float burst=pow(max(cos(ang*6.0)*0.5+0.5,0.0),12.0)*exp(-fDist*2.5);
    col+=vec3(0.15,0.2,0.3)*burst*0.06*dayF;
  }

  // ═══ Tone Mapping (ACES fitted) ═══
  col*=0.65;
  col=SAT((col*(2.51*col+0.03))/(col*(2.43*col+0.59)+0.14));

  // HDR Bloom (luminance-weighted glow)
  float lum=dot(col,vec3(0.2126,0.7152,0.0722));
  float bloomM=max(lum-0.38,0.0);
  col+=col*bloomM*0.85;

  // ═══ Spectral Dispersal (energy-dependent chromatic aberration) ═══
  vec2 caUV=gl_FragCoord.xy/uRes-0.5;
  float caDist=dot(caUV,caUV);
  // Base radial CA + energy-driven dispersion (branchless)
  float energyCA=max(lum-0.7,0.0)*0.06; // high-luminance zones get stronger CA
  float caStr=caDist*0.012+energyCA;
  col.r*=1.0+caStr;
  col.b*=1.0-caStr*0.8;
  // Bloom accumulation spectral shift
  float bloomE=dot(bloomAcc,vec3(0.33));
  col.r+=bloomE*0.015;col.b-=bloomE*0.008;

  // ═══ Vignette (cos⁴ natural falloff) ═══
  float vigR=dot(caUV,caUV)*1.8;
  float vig=1.0-vigR*0.45;
  vig*=vig;
  col*=vig;

  // ═══ Film Grain (perceptual-weighted) ═══
  float grain=(hash(gl_FragCoord.xy+fract(uTime)*137.0)-0.5)*0.018;
  col+=grain*(1.0-lum*0.6);

  // ═══ Color Grading (3-way split toning) ═══
  float lumF=dot(col,vec3(0.2126,0.7152,0.0722));
  float sW=1.0-smoothstep(0.0,0.35,lumF);
  float hW=smoothstep(0.55,1.0,lumF);
  float mW=1.0-sW-hW;
  col+=vec3(-0.006,0.008,0.022)*sW*0.5;
  col+=vec3(0.002,0.004,0.006)*mW*0.3;
  col+=vec3(0.018,0.008,-0.01)*hW*0.4;

  // ═══ Blue Noise Dithering (8-bit banding elimination) ═══
  float dNoise=fract(dot(gl_FragCoord.xy,vec2(0.7548776662,0.5698402909))+fract(uTime*7.23)*0.3819660113);
  col+=(dNoise-0.5)*0.00392157; // rcp(255.0) = 0.00392157

  // ═══ Gamma ═══
  col=pow(max(col,vec3(0)),vec3(1.0/2.2));
  gl_FragColor=vec4(col,1);
}
