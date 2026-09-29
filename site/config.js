// Public connection details for the orchard page. Both values are PUBLIC by
// design: the publishable key only reaches what row-level security allows
// (published orchards are world-readable, migration 0001). Never put the
// service_role key here.
//
// Fill these in after docs/DEPLOY-COMMUNITY.md step 5. Until then the page
// says the orchard can't be loaded yet instead of pretending.
window.LUDECK = {
  supabaseUrl: "https://xmwjmajmsqjpenegqyrq.supabase.co",
  publishableKey: "sb_publishable_xMSu0kgEgttlYFkr_Gkvsg_t8LLmNF3",
  playPackage: "com.ludeck.android",
};
