# Rewrite release quality gate

Use a clean QA installation alongside the production app. Record the APK
commit, phone and Android version, model file and checksum, tone, intensity,
length, raw output, whether the app saved or rejected it, and elapsed time.
Run the same source in Casual and Professional at Moderate and Full unless a
case says otherwise. Save the raw output even when the app rejects it.

## Scoring

For every saved result, mark **critical fail** if it changes or drops a
negation, speaker, recipient, condition, named person, quantity, date, time,
or material request; invents a fact; or translates a passage that was not to
be translated. A result rejected with a clear error protects the user but
still counts as an unsuccessful rewrite. Mark **quality fail** if Moderate or
Full returns only punctuation changes, if Casual and Professional are
indistinguishable, or if the selected tone reads as its opposite. Record
repeats separately; one successful sample cannot erase a failed repeat.

The release bar for English is zero critical failures among saved outputs,
successful rewrites for every core case, and visibly different Casual and
Professional wording in most Full runs. A typical short English message
should complete within 60 seconds on the reference Redmi 12; record the
median and slowest run. If this bar is not met, keep the affected model or
strength marked as limited and do not claim dependable tone control.

For non-English languages, retain the original script and language, all
material facts, and the requested tone. The cases below are smoke tests,
not evidence for every language. A fluent reviewer should score any language
named as reliable in the store listing. Otherwise label local multilingual
output as best effort and keep the result-level review warning.

## Core English corpus

| ID | Draft | Facts that must remain |
| --- | --- | --- |
| EN-01 | Hey sorry I cannot make the meeting on Tuesday at 3pm, can we move it to Thursday 10am? I will bring the 12 reports from Maria | Speaker cannot attend Tuesday at 3pm; asks for Thursday 10am; speaker brings 12 reports from Maria. |
| EN-02 | Hi Alex, I can't send the 4 invoices today because Priya hasn't approved them. I can send them Friday if she approves them by noon. | Four invoices; Priya has not approved; Friday is conditional on approval by noon. |
| EN-03 | We have not cancelled order 8412. Please hold the refund until Sam confirms the delivery address. | Order is not cancelled; refund is on hold until Sam confirms the address. |
| EN-04 | I paid $24.50 to Noor, not $42.50. Please correct the receipt but don't charge me again. | The two amounts and their roles, Noor, receipt correction, no new charge. |
| EN-05 | The 8am train was cancelled, so I'll reach the office at 11am and join the 9am call from home. | Cancelled 8am train, 11am arrival, 9am call from home. |
| EN-06 | If the package arrives before Friday, send it to Mia. Otherwise keep it at the office for me. | Conditional destinations and Friday boundary. |
| EN-07 | Thanks for your help yesterday. Could you send the final design to Chen and copy Elena by 5pm? | Thanks refers to yesterday; design goes to Chen with Elena copied, by 5pm. |
| EN-08 | I can review the draft, but I cannot sign it until legal approves section 3. | Reviewing is allowed; signing is blocked pending legal approval of section 3. |

## Language smoke corpus

| ID | Draft | Required invariants |
| --- | --- | --- |
| DE-01 | hallo, ich komm morgen nicht ins buero weil mein zug ausfaellt, bin ab 13 uhr online | German throughout, train cancellation, tomorrow, `13 uhr`. |
| MIX-01 | Hi Maria, ich bin ab 13 uhr online. See you tomorrow. | English/German/English order, Maria, `13 uhr`, tomorrow. |
| FR-01 | Je ne peux pas venir mardi à 15 h. Peut-on déplacer la réunion à jeudi 10 h ? | French, inability to attend Tuesday at 15 h, proposed Thursday at 10 h. |
| ES-01 | No puedo enviar los 12 informes hoy; se los llevaré a Ana el viernes. | Spanish, not today, 12 reports, Ana, Friday. |
| JA-01 | 明日の会議に行けません。金曜日の午後3時に変更できますか？資料は12部持っていきます。 | Japanese, speaker cannot attend tomorrow's meeting, asks for Friday 3pm, speaker brings 12 copies. |
| ZH-01 | 我明天不能参加会议。可以改到星期五下午三点吗？我会带十二份报告。 | Chinese, speaker cannot attend tomorrow, asks for Friday 3pm, speaker brings 12 reports. |

The remaining feature gate covers intentional spoken dictation, encrypted
backup export and restore, selected-text return, cloud routing, and encrypted
WebDAV sync. For any feature lacking real credentials, test against a local
protocol-compatible endpoint and clearly record that a real provider was not
exercised. The F-Droid release gate then requires a tagged immutable source
commit, signed APK, and passing reproducibility comparison for that APK.
