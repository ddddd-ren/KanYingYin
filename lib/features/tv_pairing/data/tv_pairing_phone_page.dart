import 'dart:convert';

String buildTvPairingPhonePage({
  required String token,
  required DateTime expiresAt,
}) {
  final tokenLiteral = jsonEncode(token);
  final expiresAtMilliseconds = expiresAt.toUtc().millisecondsSinceEpoch;
  return '''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>看影音 TV 配置</title>
  <style>
    :root{color-scheme:light;--ink:#182026;--muted:#64717c;--line:#d4dbe0;--brand:#176b5b;--brand-soft:#e1f0eb;--danger:#b83c2e;--surface:#fff;--page:#f3f5f6}
    *{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--ink);font:16px/1.5 system-ui,sans-serif}
    main{max-width:760px;margin:auto;padding:20px 14px 48px}h1{font-size:25px;margin:0}h2{font-size:18px;margin:0}p{margin:6px 0}
    .connection{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;margin-bottom:18px;padding:14px 16px;background:var(--brand-soft);border-left:4px solid var(--brand)}
    .connection strong{display:block;color:var(--brand)}.connection small{display:block;color:var(--muted)}
    section{background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:18px;margin:0 0 16px}
    label{display:block;font-weight:650;margin:12px 0 6px}input,select,textarea{width:100%;min-height:44px;border:1px solid #aab4bb;border-radius:6px;padding:9px 11px;font:inherit;background:#fff;color:var(--ink)}
    textarea{min-height:88px;resize:vertical}.row{display:grid;grid-template-columns:1fr 1fr;gap:12px}.section-title{display:flex;justify-content:space-between;gap:12px;align-items:center}
    .source{border:1px solid var(--line);border-radius:7px;padding:14px;margin-top:14px;background:#fafbfb}.provider-note{color:var(--muted);font-size:14px}
    .check{display:flex;gap:9px;align-items:center;margin-top:12px;font-weight:600}.check input{width:20px;min-height:20px;margin:0}
    .actions{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}button{min-height:44px;border:0;border-radius:6px;padding:10px 16px;font:650 15px system-ui,sans-serif;background:var(--brand);color:#fff}
    button.secondary{background:#e7ecea;color:var(--ink)}button.danger{background:var(--danger)}button:disabled{opacity:.55}.remove-source{margin-top:14px}
    #status{min-height:24px;color:var(--muted);margin-top:12px}.error,.card-error{color:var(--danger);font-weight:600}.summary{white-space:pre-wrap;background:#edf2f0;border-radius:6px;padding:12px}
    #success{text-align:center;padding:32px 18px}#success .mark{font-size:56px;color:var(--brand)}
    @media(max-width:560px){.row{grid-template-columns:1fr}.connection,.section-title{display:block}.section-title button{margin-top:10px;width:100%}}
  </style>
</head>
<body><main>
  <div class="connection">
    <div><strong id="connection-state">已连接电视</strong><small>手机和电视必须保持在同一个可信局域网</small></div>
    <div><strong id="pairing-remaining">--:--</strong><small>会话剩余时间</small></div>
  </div>
  <h1>看影音 TV 配置</h1>
  <p class="provider-note">不要在公共 Wi-Fi 使用。提交后需要在电视上用遥控器确认。</p>
  <form id="config-form">
    <section>
      <h2>基础配置</h2>
      <label for="device-name">配置名称</label>
      <input id="device-name" value="手机配置" maxlength="80" required>
      <label for="tmdb-key">TMDB API Key</label>
      <input id="tmdb-key" type="password" autocomplete="off">
    </section>
    <section>
      <h2>文件导入</h2>
      <p class="provider-note">可以直接把电视导出的配置和刮削资料发送到电视。文件只保存在本次配对的电视临时目录，配对结束后自动清理。</p>
      <label for="configuration-file">看影音配置文件（可选）</label>
      <input id="configuration-file" type="file" accept=".kyyconfig">
      <label for="configuration-password">配置文件密码</label>
      <input id="configuration-password" type="password" autocomplete="off" placeholder="选择配置文件后填写，至少 8 个字符">
      <label for="metadata-file">看影音刮削资料文件（可选）</label>
      <input id="metadata-file" type="file" accept=".kyymeta">
    </section>
    <section>
      <div class="section-title"><h2>网盘来源</h2><button class="secondary" type="button" id="add-source">添加网盘来源</button></div>
      <p class="provider-note">夸克、百度和迅雷保存凭据后，需要回到电视选择媒体目录。</p>
      <div id="sources"></div>
    </section>
    <section id="review" hidden><h2>提交摘要</h2><p class="summary" id="summary"></p></section>
    <div class="actions"><button type="submit" id="submit">发送到电视</button><button type="button" class="danger" id="cancel">取消配对</button></div>
    <p id="status" role="status"></p>
  </form>
  <section id="success" hidden>
    <div class="mark">&#10003;</div>
    <h2>电视导入成功</h2>
    <p>电视已经完成本次配置和所选文件导入。需要选择媒体目录的来源，请继续在电视端完成。</p>
  </section>
</main>
<script>
const token=$tokenLiteral;
const expiresAt=$expiresAtMilliseconds;
const form=document.getElementById('config-form');
const sources=document.getElementById('sources');
const statusNode=document.getElementById('status');
const submitButton=document.getElementById('submit');
const configurationFileInput=document.getElementById('configuration-file');
const configurationPasswordInput=document.getElementById('configuration-password');
const metadataFileInput=document.getElementById('metadata-file');
const providers={
  openList:{label:'OpenList',baseUrl:''},
  quark:{label:'夸克网盘',baseUrl:'https://pan.quark.cn'},
  baidu:{label:'百度网盘',baseUrl:'https://pan.baidu.com'},
  xunlei:{label:'迅雷网盘',baseUrl:'https://pan.xunlei.com'}
};
class FormValidationError extends Error{
  constructor(message,element){super(message);this.element=element}
}
function newSourceId(){
  const bytes=new Uint8Array(16);crypto.getRandomValues(bytes);
  return 'phone-'+Array.from(bytes,function(value){return value.toString(16).padStart(2,'0')}).join('');
}
function renderProviderFields(card){
  const type=card.querySelector('[data-field="type"]').value;
  const fields=card.querySelector('[data-provider-fields]');
  if(type==='openList'){
    fields.innerHTML='<label>服务地址</label><input data-field="baseUrl" type="url" placeholder="https://drive.example.com">'+
      '<label>媒体根目录</label><textarea data-field="rootPaths" placeholder="/电影&#10;/电视剧">/</textarea>'+
      '<div class="row"><div><label>用户名</label><input data-field="username" autocomplete="username"></div><div><label>密码</label><input data-field="password" type="password" autocomplete="current-password"></div></div>'+
      '<label class="check"><input data-field="allowSelfSignedCertificate" type="checkbox">允许自签名证书</label>';
    return;
  }
  const note='<p class="provider-note">固定服务地址：'+providers[type].baseUrl+'</p>';
  if(type==='quark'){
    fields.innerHTML=note+'<label>Cookie</label><textarea data-field="cookie" autocomplete="off"></textarea>';
    return;
  }
  if(type==='baidu'){
    fields.innerHTML=note+'<div class="row"><div><label>客户端 ID</label><input data-field="clientId" autocomplete="off"></div><div><label>客户端 Secret</label><input data-field="clientSecret" type="password" autocomplete="off"></div></div>'+
      '<label>Access Token</label><textarea data-field="accessToken" autocomplete="off"></textarea>'+
      '<label>Refresh Token</label><textarea data-field="refreshToken" autocomplete="off"></textarea>'+
      '<label>Access Token 到期时间</label><input data-field="accessTokenExpiresAt" type="datetime-local">';
    return;
  }
  fields.innerHTML=note+'<label>Refresh Token</label><textarea data-field="refreshToken" autocomplete="off"></textarea>';
}
function addSource(){
  const card=document.createElement('article');
  card.className='source';card.dataset.sourceId=newSourceId();
  card.innerHTML='<div class="row"><div><label>类型</label><select data-field="type"><option value="openList">OpenList</option><option value="quark">夸克网盘</option><option value="baidu">百度网盘</option><option value="xunlei">迅雷网盘</option></select></div><div><label>名称</label><input data-field="name" maxlength="120"></div></div>'+
    '<div data-provider-fields></div><p class="card-error" hidden></p><button type="button" class="danger remove-source">移除此来源</button>';
  card.querySelector('[data-field="type"]').addEventListener('change',function(){renderProviderFields(card)});
  card.querySelector('.remove-source').addEventListener('click',function(){card.remove()});
  sources.append(card);renderProviderFields(card);
  card.scrollIntoView({behavior:'smooth',block:'center'});
  card.querySelector('[data-field="type"]').focus();
}
function field(card,name){return card.querySelector('[data-field="'+name+'"]')}
function value(card,name){const element=field(card,name);return element?element.value.trim():''}
function requiredValue(card,name,label){
  const element=field(card,name);const result=value(card,name);
  if(!result)throw new FormValidationError('请填写'+label,element);
  return result;
}
function buildRecord(card){
  const type=value(card,'type');const name=requiredValue(card,'name','来源名称');
  const source={id:card.dataset.sourceId,type:type,name:name,baseUrl:providers[type].baseUrl,rootPaths:[],rootRefs:[],enabled:true,allowSelfSignedCertificate:false};
  const credential={};
  if(type==='openList'){
    const baseUrl=requiredValue(card,'baseUrl','服务地址');let parsed;
    try{parsed=new URL(baseUrl)}catch(_){throw new FormValidationError('服务地址格式无效',field(card,'baseUrl'))}
    if((parsed.protocol!=='http:'&&parsed.protocol!=='https:')||parsed.username||parsed.password){throw new FormValidationError('服务地址仅支持不含账号的 HTTP 或 HTTPS URL',field(card,'baseUrl'))}
    const roots=requiredValue(card,'rootPaths','媒体根目录').split(/\\r?\\n/).map(function(item){return item.trim()}).filter(Boolean);
    if(!roots.length)throw new FormValidationError('请填写至少一个媒体根目录',field(card,'rootPaths'));
    source.baseUrl=baseUrl;source.rootPaths=roots;source.allowSelfSignedCertificate=field(card,'allowSelfSignedCertificate').checked;
    const username=value(card,'username');const password=value(card,'password');if(username)credential.username=username;if(password)credential.password=password;
  }else if(type==='quark'){
    credential.cookie=requiredValue(card,'cookie','夸克 Cookie');
  }else if(type==='baidu'){
    credential.clientId=requiredValue(card,'clientId','百度客户端 ID');credential.clientSecret=requiredValue(card,'clientSecret','百度客户端 Secret');
    credential.accessToken=requiredValue(card,'accessToken','百度 Access Token');credential.refreshToken=requiredValue(card,'refreshToken','百度 Refresh Token');
    const expires=requiredValue(card,'accessTokenExpiresAt','Access Token 到期时间');const date=new Date(expires);
    if(Number.isNaN(date.getTime()))throw new FormValidationError('Access Token 到期时间无效',field(card,'accessTokenExpiresAt'));
    credential.accessTokenExpiresAt=date.toISOString();
  }else{
    credential.refreshToken=requiredValue(card,'refreshToken','迅雷 Refresh Token');
  }
  return {source:source,credential:Object.keys(credential).length?credential:null};
}
async function uploadFile(fileInput,kind){
  const file=fileInput.files&&fileInput.files[0];if(!file)return null;
  if(file.size>64*1024*1024)throw new Error('文件超过 64 MB 限制：'+file.name);
  statusNode.className='';statusNode.textContent='正在上传 '+file.name+'（'+Math.ceil(file.size/1024/1024)+' MB）';
  const response=await fetch('/api/pair/file',{method:'POST',headers:{'Content-Type':'application/octet-stream','X-Pairing-Token':token,'X-Pairing-File-Kind':kind,'X-Pairing-File-Name':encodeURIComponent(file.name)},body:file});
  let result={};try{result=await response.json()}catch(_){ }
  if(!response.ok||result.status!=='uploaded')throw new Error(result.status==='file_too_large'?'文件超过电视限制':('上传失败：'+(result.message||result.status||response.status)));
  statusNode.textContent='已上传 '+file.name;
  return result.fileId;
}
async function uploadSelectedFiles(){
  const fileIds={};
  const configFile=configurationFileInput.files&&configurationFileInput.files[0];
  const configPassword=configurationPasswordInput.value.trim();
  if(configFile){
    if(configPassword.length<8)throw new Error('配置文件密码至少 8 个字符');
    fileIds.configuration=await uploadFile(configurationFileInput,'configuration');
  }
  if(metadataFileInput.files&&metadataFileInput.files[0])fileIds.scrapedMetadata=await uploadFile(metadataFileInput,'scrapedMetadata');
  return fileIds;
}
function buildPayload(fileIds){
  const records=[];
  for(const card of sources.querySelectorAll('.source')){
    const error=card.querySelector('.card-error');error.hidden=true;error.textContent='';
    try{records.push(buildRecord(card))}catch(problem){
      if(problem instanceof FormValidationError){error.textContent=problem.message;error.hidden=false;card.scrollIntoView({behavior:'smooth',block:'center'});problem.element.focus()}
      throw problem;
    }
  }
  const payload={protocolVersion:2,deviceName:document.getElementById('device-name').value.trim(),configuration:{formatVersion:1,exportedAt:new Date().toISOString(),appVersion:'phone-web',tmdbApiKey:document.getElementById('tmdb-key').value.trim(),cloudSources:records}};
  if(Object.keys(fileIds).length){payload.fileIds=fileIds;if(fileIds.configuration)payload.configurationFilePassword=document.getElementById('configuration-password').value.trim()}
  return payload;
}
function setFormDisabled(disabled){form.querySelectorAll('input,select,textarea,button').forEach(function(node){node.disabled=disabled})}
function showSuccess(){form.hidden=true;document.getElementById('success').hidden=false;document.getElementById('connection-state').textContent='配置完成'}
function expireSession(){setFormDisabled(true);statusNode.className='error';statusNode.textContent='session_expired：配对已过期，请在电视重新生成二维码'}
function updateRemaining(){
  const remaining=Math.max(0,expiresAt-Date.now());const total=Math.ceil(remaining/1000);const minutes=Math.floor(total/60);const seconds=String(total%60).padStart(2,'0');
  document.getElementById('pairing-remaining').textContent=minutes+':'+seconds;if(remaining<=0)expireSession();
}
document.getElementById('add-source').addEventListener('click',addSource);
form.addEventListener('submit',async function(event){
  event.preventDefault();let payload,fileIds;
  try{fileIds=await uploadSelectedFiles();payload=buildPayload(fileIds)}catch(problem){statusNode.className='error';statusNode.textContent=problem.message;return}
  if(!payload.deviceName){statusNode.className='error';statusNode.textContent='请填写配置名称';document.getElementById('device-name').focus();return}
  const counts={openList:0,quark:0,baidu:0,xunlei:0};payload.configuration.cloudSources.forEach(function(record){counts[record.source.type]++});
  document.getElementById('summary').textContent='TMDB：'+(payload.fileIds&&payload.fileIds.configuration?'由配置文件导入':(payload.configuration.tmdbApiKey?'将更新':'保留电视当前配置'))+'\\n网盘来源：'+payload.configuration.cloudSources.length+' 个\\nOpenList '+counts.openList+' · 夸克 '+counts.quark+' · 百度 '+counts.baidu+' · 迅雷 '+counts.xunlei+(payload.fileIds&&payload.fileIds.configuration?'\\n配置文件：将导入':'')+(payload.fileIds&&payload.fileIds.scrapedMetadata?'\\n刮削资料：将导入':'');
  document.getElementById('review').hidden=false;statusNode.className='';statusNode.textContent='等待电视确认';submitButton.disabled=true;
  try{
    const response=await fetch('/api/pair',{method:'POST',headers:{'Content-Type':'application/json','X-Pairing-Token':token},body:JSON.stringify(payload)});
    const result=await response.json();
    if(response.ok&&result.status==='paired'){statusNode.textContent='电视配置和文件导入成功';showSuccess();return}
    if(result.status==='rejected_on_tv'){statusNode.textContent='电视已拒绝，可修改后重新发送';return}
    if(result.status==='apply_failed'){statusNode.className='error';statusNode.textContent='电视写入失败，原配置已保留';return}
    if(result.status==='session_expired'){expireSession();return}
    statusNode.className='error';statusNode.textContent='提交失败，请返回电视重试';
  }catch(_){statusNode.className='error';statusNode.textContent='无法连接电视，请确认同一局域网且路由器未启用 AP 隔离'}
  finally{if(!form.hidden&&Date.now()<expiresAt)submitButton.disabled=false}
});
document.getElementById('cancel').addEventListener('click',async function(){
  try{await fetch('/api/cancel',{method:'POST',headers:{'Content-Type':'application/json','X-Pairing-Token':token},body:'{}'})}finally{setFormDisabled(true);statusNode.textContent='配对已取消'}
});
updateRemaining();setInterval(updateRemaining,1000);
</script></body></html>''';
}
