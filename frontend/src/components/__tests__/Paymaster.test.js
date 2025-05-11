// frontend/src/components/__tests__/Paymaster.test.js
import { render, screen } from "@testing-library/react";
import Paymaster from "../Paymaster";

test("shows funding UI for funders", () => {
  render(<Paymaster />);
  expect(screen.getByText("Fund Paymaster")).toBeInTheDocument();
});
