// Redirect legacy create-post route into the news feed command desk modal.

import { Navigate } from "react-router-dom";

export function DepartmentCreatePostPage() {
  return <Navigate replace to="/department/news-feed?compose=1" />;
}
