# Case Comment Submitter

Submit Salesforce Case Comments through a simple UI and Apex-backed logic.

## What this is

**Case Comment Submitter** is a Salesforce customization (Apex + HTML/CSS/JavaScript) that helps users add comments to existing **Case** records quickly and consistently.

## Interactive Demo

A no-org-required interactive static demo is included in the repo.

### Run locally

Open `demo/index.html` in a browser.

### What the demo shows

- Case header with case number, subject, and status
- Existing comment timeline
- New comment composer with live character count
- Sort toggle for newest/oldest comments
- Simulated attachments
- Simulated submit flow with toast feedback
- Simulated case status changes based on comment author type

### Optional GitHub Pages hosting

Because the demo is static HTML/CSS/JS, it can also be hosted with GitHub Pages by serving the `demo/` directory or repository root.

## Key features

- Submit a comment to a selected Case
- Basic validation (e.g., required fields)
- Designed to work within standard Salesforce Case/Case Comment behavior
- Lightweight UI (HTML/CSS/JS) with Apex handling server-side operations

## Who this is for

- **End users / Support agents:** Add comments to customer Cases.
- **Admins:** Deploy and grant access.
- **Developers:** Extend the UI, validations, or submission behavior.

---

## End User Guide

### Accessing the tool
1. Open Salesforce.
2. Navigate to the **Case** you want to update.
3. Open the **Case Comment Submitter** component/page (your org may expose this as:
   - a Lightning App page component,
   - a Lightning record page section,
   - a utility item,
   - or a tab).

If you don’t see it, contact your Salesforce admin to confirm you have access.

### Submitting a case comment
1. Confirm you’re on the correct **Case**.
2. Enter your comment in the comment text box.
3. Click **Submit** (or equivalent action button).

### What happens after submission
- The comment is saved to the Case (as a Case Comment / Feed item depending on how this repo is implemented in your org).
- You should see a success message and/or the comment appear in the Case’s comments/activity area.

### Tips for successful comments
- Don’t include sensitive data unless your process explicitly allows it.
- Be specific: include steps taken, customer impact, and next actions.
- If your org uses internal vs. public comments, confirm which type you’re submitting (if the UI provides an option).

### Common user issues
**“I clicked Submit but nothing happened.”**
- Refresh the page and try again.
- Ensure the comment field isn’t empty.
- If it still fails, report the time and Case Number to your admin.

**“I don’t have permission.”**
- You likely need access to the component/page and permission to create Case Comments.
- Ask your admin to grant the correct permission set/profile access.

---

## Admin Guide (Setup)

### Prerequisites
- Salesforce org with Cases enabled
- Permissions to deploy metadata (Admin / Deployment privileges)
- A deployment method (Salesforce CLI, changesets, or DevOps tool)

### Deploy
- Deploy metadata to the target org using your preferred method.
- Assign any Permission Sets included by this repo (or update profiles accordingly).

### Permissions to verify
Users typically need:
- Read access to **Case**
- Create access to **Case Comment** (and read access if they need to view)
- Access to the page/component/tab where the tool is placed
- Any Apex class access required by the UI (if not handled via permission set)

---

## Developer Notes

### Tech used (from repo language breakdown)
- Apex
- JavaScript
- HTML
- CSS

### Typical extension points
- Add stronger validation (length limits, required patterns, restricted words)
- Add support for internal vs. customer-facing comments
- Add error handling with more actionable messages
- Add logging (platform events/custom object) for auditing submissions

---

## Troubleshooting

- Verify the Apex class/controller is deployed and accessible.
- Check Salesforce debug logs for exceptions during submit.
- Confirm the running user has required object and field permissions.
- Confirm the Case Id/context is being passed correctly to the UI.

---

## Contributing

1. Create a branch
2. Make changes with clear commit messages
3. Open a pull request describing the behavior change and test notes

---

## License

Add your license information here (e.g., MIT) or include a `LICENSE` file.
