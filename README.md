# Warranty Logbook

A responsive warranty logbook. The site uses Supabase for email/password sign-in, branch access, service records, and private slip attachments.

## Supabase setup

1. Open the Supabase project SQL Editor.
2. Run [`supabase-setup.sql`](./supabase-setup.sql).
   - The script is safe to rerun after the existing schema has been created. It adds the recently authenticated record-deletion RPC, ticket-number and serial-number columns, and enables Realtime updates for service records. Run it again whenever these database functions change; publishing the website does not update the Supabase database.
3. In Supabase Authentication URL settings, set the Site URL to the GitHub Pages address and add that same address to the allowed redirect URLs.
4. For reliable signup confirmation delivery, configure an SMTP provider in Supabase Authentication settings. The built-in email service is rate-limited and intended for testing. Users can request another confirmation email from the signup screen.

The project URL and publishable browser key are configured in `index.html`. Publishable keys are intended for browser use; never add a Supabase secret or `service_role` key to this repository.

## Publish with GitHub Pages

1. Create a GitHub repository named `warranty-logbook` and push these project files to its `main` branch.
2. In the repository, open **Settings → Pages** and set the build and deployment source to **GitHub Actions**.
3. The workflow in `.github/workflows/pages.yml` deploys the site after each push to `main`. GitHub shows the published URL in **Settings → Pages** and in the workflow run.
4. Add the published URL to Supabase Authentication URL settings, then open that URL and create your account.

The site uses the same account on phone and computer. Supabase row-level security limits each account to branches it belongs to.
Enter a ticket number when adding each record. Ticket numbers must be unique within their branch; existing records keep their current displayed numbers. Changes to records appear on other open devices through Supabase Realtime.
Deleting a record asks for your account password once. Supabase verifies that the new sign-in session was created within the last five minutes before allowing deletion.
When adding a service slip, image text is recognized in the browser; photos are not sent to an OCR service. Check and correct the extracted customer, item, printed slip number, serial number, and date before saving. The image is uploaded to the branch's private attachment storage only when you save the record. OCR needs an internet connection to load its browser library and English language data.