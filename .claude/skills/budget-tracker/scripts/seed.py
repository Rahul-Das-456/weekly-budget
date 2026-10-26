"""Write a test save file into the simulator app's Documents folder. Dates use Apple's 2001 reference epoch."""
import sys, json, time, datetime, uuid, os

scen, docs = sys.argv[1], sys.argv[2]
REF = 978307200
def ts(d): return time.mktime(d.timetuple()) - REF
today = datetime.datetime.combine(datetime.date.today(), datetime.time())
monday = today - datetime.timedelta(days=today.weekday())
last_monday = monday - datetime.timedelta(days=7)
for f in ("budget.json", "budget-v2.json"):
    p = os.path.join(docs, f)
    if scen != "keep" and os.path.exists(p): os.remove(p)

def cat(name, icon, budget, rollover=0):
    return {"id": str(uuid.uuid4()).upper(), "name": name, "icon": icon, "budget": budget, "rollover": rollover}
def exp(c, amt, note, day):
    return {"id": str(uuid.uuid4()).upper(), "categoryID": c["id"], "amount": amt, "note": note, "date": ts(day)}

if scen in ("thisweek", "lastweek"):
    food, groc, ent, rides = cat("Food", "fork.knife", 100), cat("Groceries", "cart", 100), cat("Entertainment", "ticket", 50), cat("Uber / Lyft", "car", 50)
    cats = [food, groc, ent, rides]
    if scen == "thisweek":
        groc["rollover"] = 40
        coffee = cat("Coffee", "cup.and.saucer", 25); cats.append(coffee)
        start, exps = monday, [exp(food, 120, "Chipotle", monday), exp(rides, 18.5, "Uber", monday), exp(coffee, 6.75, "Latte", today)]
    else:
        start, exps = last_monday, [exp(food, 30, "Chipotle", last_monday + datetime.timedelta(days=2)),
                                    exp(rides, 60, "Uber", last_monday + datetime.timedelta(days=3))]
    json.dump({"categories": cats, "weekStart": ts(start), "expenses": exps, "hasSetBudgets": True},
              open(os.path.join(docs, "budget-v2.json"), "w"))
elif scen == "legacy":
    e = lambda c, a, n, d: {"id": str(uuid.uuid4()).upper(), "category": c, "amount": a, "note": n, "date": ts(last_monday + datetime.timedelta(days=d))}
    json.dump({"budgets": ["food", 100, "groceries", 100, "entertainment", 50, "rides", 50], "weekStart": ts(last_monday),
               "expenses": [e("food", 30, "Chipotle", 2), e("rides", 60, "Uber", 3)], "hasSetBudgets": True},
              open(os.path.join(docs, "budget.json"), "w"))
print("Seeded:", scen)
