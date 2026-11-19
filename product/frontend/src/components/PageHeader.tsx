import { Heading, Text, VStack } from "@chakra-ui/react";

export interface PageHeaderProps {
  title: string;
  subtitle: string;
}

/**
 * Shared page header from the mockups: a bold title with a muted descriptive
 * subtitle. Kept tiny on purpose so the Account and directory pages use one copy.
 */
export default function PageHeader({ title, subtitle }: PageHeaderProps) {
  return (
    <VStack as="header" spacing={1} align="start">
      <Heading
        as="h1"
        fontSize={{ base: "24px", lg: "28px" }}
        fontWeight={700}
        letterSpacing="-0.01em"
      >
        {title}
      </Heading>
      <Text fontSize={{ base: "14px", lg: "15px" }} color="muted">
        {subtitle}
      </Text>
    </VStack>
  );
}
