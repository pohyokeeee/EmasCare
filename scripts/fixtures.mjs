import {Timestamp} from 'firebase-admin/firestore';
import {createHash} from 'node:crypto';

const tupleId = (...parts) => createHash('sha256').update(JSON.stringify(parts)).digest('hex');

export const townshipId = 'township_demo';
export const demoPassword = 'EmasCare-local-2026!';
export const demoAccounts = [
  {uid:'elder_demo', email:'elder@emascare.test', displayName:'Demo Elder', role:'elder', householdId:'household_demo'},
  {uid:'family_demo', email:'family@emascare.test', displayName:'Demo Family', role:'family', householdId:'household_demo'},
  {uid:'helper_demo', email:'helper@emascare.test', displayName:'Demo Helper', role:'helper', householdId:'household_helper'},
  {uid:'coordinator_demo', email:'coordinator@emascare.test', displayName:'Demo Coordinator', role:'coordinator', householdId:null},
  {uid:'elder_solo', email:'solo@emascare.test', displayName:'Standalone Elder', role:'elder', householdId:'household_solo'},
  {uid:'family_unrelated', email:'unrelated@emascare.test', displayName:'Unrelated Family', role:'family', householdId:'household_other'},
];

// Executable emulator data, independent of the ignored UI-only contract examples.
// No completed history or earning amounts are invented while policy is pending.
export function fixtureDocuments(now = new Date()) {
  const at = Timestamp.fromDate(now);
  const metadata = {createdAt:at, updatedAt:at};
  const future = (days, hour) => {
    const date = new Date(now);
    date.setUTCDate(date.getUTCDate() + days);
    date.setUTCHours(hour, 0, 0, 0);
    return Timestamp.fromDate(date);
  };
  const documents = [];
  const add = (path, data) => documents.push({path, data});
  const localDate = (date) => new Intl.DateTimeFormat('en-CA', {timeZone:'Asia/Kuala_Lumpur', year:'numeric', month:'2-digit', day:'2-digit'}).format(date);
  for (const account of demoAccounts) {
    const {uid, email: _email, ...profile} = account;
    add(`users/${uid}`, {...profile, townshipId, locale:'en', ...metadata});
    if (['elder','helper'].includes(account.role)) {
      add(`wallets/${uid}`, {ownerUid:uid, townshipId, balance:0, updatedAt:at});
    }
    if (account.role === 'elder') {
      const date = localDate(now);
      const dueLocalTime = uid === 'elder_solo' ? '00:00' : '09:00';
      const graceMinutes = uid === 'elder_solo' ? 0 : 30;
      const dueAt = Timestamp.fromDate(new Date(`${date}T${dueLocalTime}:00+08:00`));
      const graceEndsAt = Timestamp.fromMillis(dueAt.toMillis() + graceMinutes * 60000);
      const state = at.toMillis() < dueAt.toMillis() ? 'pending' : at.toMillis() < graceEndsAt.toMillis() ? 'reminded' : 'missed';
      add(`elderSettings/${uid}`, {familySharingEnabled:uid === 'elder_demo', familyBookingEnabled:uid === 'elder_demo',
        dueLocalTime, graceMinutes, pausedOn:null, ...metadata});
      add(`checkins/${uid}_${date}`, {elderId:uid,townshipId,localDate:date,state,dueAt,graceEndsAt,
        submittedAt:null,recordedBy:null,source:null,...metadata});
      add(`dailyStatuses/${uid}_${date}`, {elderId:uid,householdId:account.householdId,localDate:date,
        state,submittedAt:null,updatedAt:at});
    }
  }
  add('households/household_demo', {townshipId, memberUids:['elder_demo','family_demo'], elderIds:['elder_demo'],
    familyUids:['family_demo'], elderAccess:{elder_demo:{displayName:'Demo Elder', familySharingEnabled:true, familyBookingEnabled:true}}, ...metadata});
  for (const [id, member, elders, family] of [
    ['household_helper','helper_demo',[],[]],
    ['household_solo','elder_solo',['elder_solo'],[]],
    ['household_other','family_unrelated',[],['family_unrelated']],
  ]) add(`households/${id}`, {townshipId, memberUids:[member], elderIds:elders, familyUids:family,
    elderAccess:id === 'household_solo' ? {elder_solo:{displayName:'Standalone Elder', familySharingEnabled:false, familyBookingEnabled:false}} : {}, ...metadata});
  // Synthetic full-day demo schedule lets the same walkthrough run at any hour.
  const slots = Array.from({length:7}, (_, i) => ({weekday:i+1, startMinute:0, endMinute:1440}));
  const tasks = ['walk_with_me','sit_with_me','phone_help','carry_light_item'];
  add('helperProfiles/helper_demo', {approved:true, tier:'T3', languages:['bm','en'], gender:'female',
    allowedTasks:tasks, available:true, availabilitySlots:slots, ...metadata});
  add('pairings/pairing_demo', {townshipId, elderId:'elder_demo', helperId:'helper_demo', active:true,
    elderAccepted:true, helperAccepted:true, trialStartsOn:localDate(new Date(now.getTime()-86400000)),
    trialEndsOn:localDate(new Date(now.getTime()+14*86400000)), cadence:slots, allowedTasks:tasks, isDemoSeed:true, ...metadata});
  // Explicit assigned-state fixture: no fake completion or rewards. The helper
  // can accept/start/finish now, followed by separate participant confirmations.
  const startsAt = Timestamp.fromMillis(Math.floor(now.getTime()/60000)*60000-15*60000);
  const endsAt = Timestamp.fromMillis(startsAt.toMillis()+10*60000);
  const assignedAt = Timestamp.fromMillis(startsAt.toMillis()-60000);
  add('requests/request_demo_ready', {townshipId,householdId:'household_demo',elderId:'elder_demo',createdBy:'elder_demo',
    activityId:null,placeId:null,startsAt,endsAt,taskType:'phone_help',preferredLanguage:'en',preferredHelperGender:'any',
    state:'assigned',pairingId:'pairing_demo',helperId:'helper_demo',elderDisplayName:'Demo Elder',
    helperDisplay:{displayName:'Demo Helper',tier:'T3'},assignedAt,acceptedAt:null,startedAt:null,finishedAt:null,
    elderConfirmation:null,helperConfirmation:null,completedAt:null,cancelledAt:null,completionEventId:null,
    participationIds:{elder:null,helper:null},createdAt:assignedAt,updatedAt:assignedAt});
  for (let cursor=startsAt.toMillis();cursor<endsAt.toMillis();) {
    const date = localDate(new Date(cursor));
    add(`helperReservations/${tupleId('helper-date','helper_demo',date)}`, {helperId:'helper_demo',townshipId,localDate:date,
      slots:[{requestId:'request_demo_ready',startsAt,endsAt}],updatedAt:assignedAt});
    cursor = new Date(`${date}T00:00:00+08:00`).getTime()+86400000;
  }
  for (const [id,name,minutes] of [['place_garden','Community Garden',10],['place_hall','Community Hall',5]]) {
    add(`places/${id}`, {townshipId, name, stepFree:true, accessibleToilet:true, seating:true, walkMinutes:minutes,
      notes:{bm:'Nota akses contoh; semak keadaan semasa.',en:'Illustrative access notes; check current conditions.'},
      mapsUrl:'https://maps.google.com/?q=community+hall', imageAsset:null,
      liveStatus:id === 'place_garden' ? {level:'warning',text:'Demo: wet path; coordinator review required.',updatedAt:at,expiresAt:future(1,12),setBy:'coordinator_demo'} : null, ...metadata});
  }
  for (const [id,placeId,title,days] of [
    ['activity_garden','place_garden',{bm:'Jalan di taman',en:'Garden walk'},1],
    ['activity_hall','place_hall',{bm:'Pertemuan komuniti',en:'Community gathering'},2],
  ]) add(`activities/${id}`, {townshipId,title,placeId,participationMode:'in_person',startsAt:future(days,1),endsAt:future(days,2),language:'en',...metadata});
  add('voucherCatalog/voucher_demo', {townshipId,title:{bm:'Baucar contoh',en:'Mock voucher'},costCoins:100,active:true,isDemo:true,...metadata});
  return documents;
}
